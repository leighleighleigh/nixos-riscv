build:
  nix --print-build-logs build ".#hydraJobs.duo"
qemu:
  nix --print-build-logs build ".#hydraJobs.qemu"
