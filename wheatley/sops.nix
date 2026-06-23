{ config, lib, pkgs, ... }: {
  # wheatley decrypts its secrets with the age key derived from its SSH host
  # key. Public key lives in ../.sops.yaml as &wheatley. Decrypted secrets are
  # placed under /run/secrets (tmpfs).
  #
  # Read the key from /persist directly, NOT /etc/ssh. The root is rolled back
  # to a blank snapshot on every boot, and /etc/ssh is only a stage-2 bind mount
  # from /persist that isn't mounted yet when sops' setupSecrets runs in early
  # activation -- at that point /etc/ssh is the wiped, empty root dir. /persist
  # is mounted back in initrd (neededForBoot), so the key is available there.
  sops.defaultSopsFile = ../secrets/wheatley.yaml;
  sops.age.sshKeyPaths = [ "/persist/etc/ssh/ssh_host_ed25519_key" ];
}
