return {
  name = "flatpak install local ref file",
  request = {
    action = "install",
    system = "flatpak",
    localPath = "/tmp/firefox.flatpakref",
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
      match = "flatpak install --user --noninteractive --assumeyes --from '/tmp/firefox.flatpakref'",
      exitCode = 0,
      stdout = "installed\n",
      stderr = "",
      success = true,
    },
  },
  expect = {
    success = true,
    commands = { "flatpak install --user --noninteractive --assumeyes --from '/tmp/firefox.flatpakref'" },
    stdout = { "installed\n" },
    events = { "installed", "success" },
    eventPayloads = {
      installed = "{localTarget=true, path=/tmp/firefox.flatpakref}",
      success = "ok",
    },
  }
}
