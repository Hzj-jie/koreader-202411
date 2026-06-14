local gettext = require("gettext")
return {
  name = "vocabbuilder",
  fullname = gettext("Vocabulary builder"),
  description = gettext(
    [[This plugin processes dictionary word lookups and uses spaced repetition to help you remember new words.]]
  ),
}
