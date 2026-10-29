#!/usr/bin/env bash
# Build on the user's Ubuntu Quartus host; all remote files stay in ~/dev/mister.
set -euo pipefail
cd "$(dirname "$0")"
mode=${1:-remote}
image=${QUARTUS_IMAGE:-theypsilon/quartus-lite-c5:17.0.2.docker0}
remote_dir=dev/mister/TI59
case "$mode" in
  remote)
    make prepare
    ssh ubuntu "mkdir -p ~/$remote_dir"
    rsync -az --exclude=.git --exclude=research --exclude=build --exclude=db \
      --exclude=incremental_db --exclude=output_files --exclude=releases \
      ./ "ubuntu:$remote_dir/"
    ssh ubuntu "cd ~/$remote_dir && QUARTUS_IMAGE='$image' bash build.sh docker"
    mkdir -p output_files build
    rsync -az "ubuntu:$remote_dir/output_files/" output_files/
    rsync -az "ubuntu:$remote_dir/build/quartus.log" build/
    ;;
  docker)
    # Count whole flows, not the fitter subprocesses of those same flows.
    jobs=$(( $( (pgrep -af '[q]uartus_sh.*--flow' || true) | wc -l) ))
    if [ "$jobs" -ge 2 ]; then echo 'Both Ubuntu Quartus slots are occupied.' >&2; exit 1; fi
    mkdir -p build
    docker run --rm --name ti59-quartus -v "$PWD:/work" -w /work "$image" \
      /opt/intelFPGA_lite/quartus/bin/quartus_sh --flow compile TI59 >build/quartus.log 2>&1
    if rg -q 'Timing requirements not met' build/quartus.log; then
      echo 'RBF generated, but timing failed. See build/quartus.log.' >&2; exit 2
    fi
    tail -15 build/quartus.log
    ;;
  *) echo 'Usage: ./build.sh [remote|docker]' >&2; exit 1;;
esac
