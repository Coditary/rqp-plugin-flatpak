return {
  name = "flatpak info installed ref",
  request = {
    action = "info",
    system = "flatpak",
    prompt = "com.visualstudio.code",
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
      match = "flatpak info --user --show-ref --show-origin --show-runtime --show-sdk 'com.visualstudio.code'",
      exitCode = 0,
      stdout = "app/com.visualstudio.code/x86_64/stable flathub org.freedesktop.Sdk/x86_64/24.08 org.freedesktop.Sdk/x86_64/24.08\n",
      stderr = "",
      success = true,
    },
  },
  expect = {
    success = true,
    events = { "informed" },
    resultCount = 1,
    resultName = "com.visualstudio.code",
  }
}
