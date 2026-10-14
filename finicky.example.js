// Finicky routes links opened from other apps to the right browser profile.
// Links with no rule go to Finicky Picker, which asks which profile to use and,
// if you tick the box, saves the choice in the learned block below.
// Hold Option while clicking a link to get the picker again.
const pickerBrowser = "__BROWSER__";
const picker = { name: "__HOME__/Applications/Finicky Picker.app", appType: "path" };
const profile = (name) => ({ name: pickerBrowser, profile: name });

// learned:start
const learned = {};
// learned:end

const host = (url) => url.hostname.replace(/^www\./, "");

export default {
  defaultBrowser: picker,
  handlers: [
    {
      match: () => finicky.getModifierKeys().option,
      browser: picker,
    },
    // Fixed rules go here, using the profile names from your browser's profile menu:
    // { match: ["*.mycompany.com/*"], browser: profile("Work") },
    {
      match: (url) => host(url) in learned,
      browser: (url) => profile(learned[host(url)]),
    },
  ],
};
