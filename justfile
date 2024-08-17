build:
  nix --print-build-logs build ".#hydraJobs.duos"
qemu:
  nix --print-build-logs build ".#hydraJobs.qemu"
