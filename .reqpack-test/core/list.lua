return {
  name = "flatpak list installed refs",
  request = {
    action = "list",
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
      match = "flatpak list --user --app --columns=application,ref,version,branch,arch,origin,name,description",
      exitCode = 0,
      stdout = "org.mozilla.firefox\torg.mozilla.firefox/x86_64/stable\t124.0\tstable\tx86_64\tflathub\tFirefox\tWeb Browser\n",
      stderr = "",
      success = true,
    },
    {
      match = "flatpak list --user --runtime --columns=application,ref,version,branch,arch,origin,name,description",
      exitCode = 0,
      stdout = "org.freedesktop.Platform\torg.freedesktop.Platform/x86_64/24.08\t24.08\t24.08\tx86_64\tflathub\tFreedesktop Platform\tRuntime platform\n",
      stderr = "",
      success = true,
    },
  },
  expect = {
    success = true,
    events = { "listed" },
    resultCount = 2,
    resultName = "org.mozilla.firefox",
    resultVersion = "124.0",
  }
}
