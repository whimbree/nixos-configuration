{ config, lib, pkgs, ... }:

{
  microvm = {
    hypervisor = "cloud-hypervisor";
    mem = 3 * 1024;
    vcpu = 2;
  };

  system.stateVersion = "25.05";
}
