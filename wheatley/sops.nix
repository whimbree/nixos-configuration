{ config, lib, pkgs, ... }: {
  # wheatley decrypts its secrets with the age key derived from its SSH host
  # key (persisted via /persist/etc/ssh). Public key lives in ../.sops.yaml as
  # &wheatley. Decrypted secrets are placed under /run/secrets (tmpfs).
  sops.defaultSopsFile = ../secrets/wheatley.yaml;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
}
