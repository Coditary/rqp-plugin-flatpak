return {
  name = "flatpak update installed ref",
  request = {
    action = "update",
    system = "flatpak",
    packages = {
      { action = "update", name = "org.mozilla.firefox" }
    },
  },
  fakeExec = {
    {
      match = "command -v flatpak >/dev/null 2>&1",
      exitCode = 0,
      stdout = "",
      stderr = "",
      success = true,
    },
    {
      match = "flatpak list --user --columns=application,ref",
      exitCode = 0,
      stdout = "org.mozilla.firefox\torg.mozilla.firefox/x86_64/stable\n",
      stderr = "",
      success = true,
    },
    {
      match = "flatpak remote-ls --user --updates --columns=application,ref",
      exitCode = 0,
      stdout = "org.mozilla.firefox\torg.mozilla.firefox/x86_64/stable\n",
      stderr = "",
      success = true,
    },
    {
      match = "flatpak update --user --noninteractive --assumeyes 'org.mozilla.firefox'",
      exitCode = 0,
      stdout = "updated\n",
      stderr = "",
      success = true,
    },
  },
  expect = {
    success = true,
    commands = { "flatpak update --user --noninteractive --assumeyes 'org.mozilla.firefox'" },
    stdout = { "updated\n" },
    events = { "updated", "success" },
    eventPayloads = {
      success = "ok",
    },
  }
}
