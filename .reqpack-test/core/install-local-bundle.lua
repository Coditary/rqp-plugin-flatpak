return {
  name = "flatpak install local bundle",
  request = {
    action = "install",
    system = "flatpak",
    localPath = "/tmp/firefox.flatpak",
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
      match = "flatpak install --user --noninteractive --assumeyes --bundle '/tmp/firefox.flatpak'",
      exitCode = 0,
      stdout = "installed\n",
      stderr = "",
      success = true,
    },
  },
  expect = {
    success = true,
    commands = { "flatpak install --user --noninteractive --assumeyes --bundle '/tmp/firefox.flatpak'" },
    stdout = { "installed\n" },
    events = { "installed", "success" },
    eventPayloads = {
      installed = "{localTarget=true, path=/tmp/firefox.flatpak}",
      success = "ok",
    },
  }
}
