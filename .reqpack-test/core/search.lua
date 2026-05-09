return {
  name = "flatpak search remote refs",
  request = {
    action = "search",
    system = "flatpak",
    prompt = "firefox",
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
      match = "flatpak search --user --columns=application,version,branch,remotes,name,description 'firefox'",
      exitCode = 0,
      stdout = "org.mozilla.firefox\t124.0\tstable\tflathub\tFirefox\tWeb Browser\n",
      stderr = "",
      success = true,
    },
  },
  expect = {
    success = true,
    events = { "searched" },
    resultCount = 1,
    resultName = "org.mozilla.firefox",
    resultVersion = "124.0",
  }
}
