return {
  name = "flatpak outdated refs",
  request = {
    action = "outdated",
    system = "flatpak",
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
      match = "flatpak remote-ls --user --updates --app --columns=application,ref,version,branch,arch,origin,name,description",
      exitCode = 0,
      stdout = "org.mozilla.firefox\torg.mozilla.firefox/x86_64/stable\t125.0\tstable\tx86_64\tflathub\tFirefox\tWeb Browser\n",
      stderr = "",
      success = true,
    },
    {
      match = "flatpak remote-ls --user --updates --runtime --columns=application,ref,version,branch,arch,origin,name,description",
      exitCode = 0,
      stdout = "",
      stderr = "",
      success = true,
    },
  },
  expect = {
    success = true,
    events = { "outdated" },
    resultCount = 1,
    resultName = "org.mozilla.firefox",
    resultVersion = "125.0",
  }
}
