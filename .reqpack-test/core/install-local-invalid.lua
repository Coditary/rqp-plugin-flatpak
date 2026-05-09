return {
  name = "flatpak install local invalid artifact",
  request = {
    action = "install",
    system = "flatpak",
    localPath = "/tmp/firefox.zip",
  },
  fakeExec = {
    {
      match = "command -v flatpak >/dev/null 2>&1",
      exitCode = 0,
      stdout = "",
      stderr = "",
      success = true,
    },
  },
  expect = {
    success = false,
    events = { "failed" },
    eventPayloads = {
      failed = "unsupported local Flatpak artifact type",
    },
  }
}
