{ ... }: {
  # Declarative users only — passwd changes won't survive a rebuild.
  users.mutableUsers = false;

  users.users.bree = {
    isNormalUser = true;
    home = "/home/bree";
    hashedPassword =
      "$6$qUgza/1z1AzqiXCU$5QvUzVCAGY0FslF.hamAUXyAHDnGd3wZK.qAhMHXNWMJ961BwLNrGHWHBnnNBdtJPewM9KwSO3Xe1zQNgfQWA.";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINfnYIsi2Obl8sSRYvyoUHPRanfUqwMhtp9c79tQofkZ whimbree@pm.me"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH+baB6WxRgTBFQLoNNcw706A5Egd3gS5hCWl0nMDE+q bree@megakill"
    ];
  };

  users.users.root.hashedPassword =
    "$6$92pB6eAOE8ZHfqih$aMjx7DKyP2YdLokS0E3VN2ZfnQYWO1I46VwdoLfGB2Xy3m8DgJTF8/8vT6b6zRPfhG/Xs.5YSQcQmTHUyDiat1";
}
