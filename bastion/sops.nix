{ ... }: {
  # bastion decrypts its own secrets with the age key derived from its SSH host
  # key. Public key lives in ../.sops.yaml as &bastion. Decrypted secrets are
  # placed under /run/secrets (tmpfs). Per-MicroVM secrets are separate; see
  # modules/sops-vm-keys.nix.
  #
  # Read the key from /persist directly, NOT /etc/ssh. The root is rolled back
  # to a blank snapshot on every boot, and /etc/ssh is only a stage-2 link to
  # /persist that isn't in place yet when sops' setupSecrets runs in early
  # activation. /persist is mounted in initrd (neededForBoot), so the key is
  # available there.
  sops.defaultSopsFile = ../secrets/bastion.yaml;
  sops.age.sshKeyPaths = [ "/persist/etc/ssh/ssh_host_ed25519_key" ];

  # Publish-only token for ntfy.whimsical.cloud (see microvm-weekly-update.nix).
  sops.secrets.ntfy_token = { };
}
