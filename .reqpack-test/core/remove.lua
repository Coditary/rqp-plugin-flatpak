return {
  name = "flatpak remove installed ref",
  request = {
    action = "remove",
    system = "flatpak",
    packages = {
      { action = "remove", name = "org.mozilla.firefox" }
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
      match = "flatpak uninstall --user --noninteractive --assumeyes 'org.mozilla.firefox'",
      exitCode = 0,
      stdout = "removed\n",
      stderr = "",
      success = true,
    },
  },
  expect = {
    success = true,
    commands = { "flatpak uninstall --user --noninteractive --assumeyes 'org.mozilla.firefox'" },
    stdout = { "removed\n" },
    events = { "deleted", "success" },
    eventPayloads = {
      success = "ok",
    },
  }
}
