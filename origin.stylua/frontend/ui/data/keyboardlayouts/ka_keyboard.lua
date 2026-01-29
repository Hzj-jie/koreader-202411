local en_popup = dofile("frontend/ui/data/keyboardlayouts/keypopup/en_popup.lua")
local ka_popup = dofile("frontend/ui/data/keyboardlayouts/keypopup/ka_popup.lua")
local com = en_popup.com -- comma (,)
local prd = en_popup.prd -- period (.)
local _at = en_popup._at
local _eq = en_popup._eq -- equals sign (=)
local _a_ = ka_popup._a_
local _c_ = ka_popup._c_
local _e_ = ka_popup._e_
local _f_ = ka_popup._f_
local _g_ = ka_popup._g_
local _h_ = ka_popup._h_
local _i_ = ka_popup._i_
local _j_ = ka_popup._j_
local _n_ = ka_popup._n_
local _r_ = ka_popup._r_
local _s_ = ka_popup._s_
local _t_ = ka_popup._t_
local _v_ = ka_popup._v_
local _w_ = ka_popup._w_
local _x_ = ka_popup._x_
local _y_ = ka_popup._y_
local _z_ = ka_popup._z_

return {
  min_layer = 1,
  max_layer = 8,
  shiftmode_keys = { [""] = true, ["1/2"] = true, ["2/2"] = true },
  symbolmode_keys = { ["123"] = true, ["აბგ"] = true },
  utf8mode_keys = { ["🌐"] = true },
  umlautmode_keys = { ["Äéß"] = true },
  keys = {
    -- first row
    { --  1       2       3       4       5       6       7       8
      { "Q", "ქ", "„", "0", "Å", "å", "1", "ª" },
      { "ჭ", _w_, "!", "1", "Ä", "ä", "2", "º" },
      { "E", _e_, _at, "2", "Ö", "ö", "3", "¡" },
      { "ღ", _r_, "#", "3", "ß", "ß", "4", "¿" },
      { "თ", _t_, "+", _eq, "À", "à", "5", "¼" },
      { "Y", _y_, "€", "(", "Â", "â", "6", "½" },
      { "U", "უ", "‰", ")", "Æ", "æ", "7", "¾" },
      { "I", _i_, "|", "\\", "Ü", "ü", "8", "©" },
      { "O", "ო", "?", "/", "È", "è", "9", "®" },
      { "P", "პ", "~", "`", "É", "é", "0", "™" },
    },
    -- second row
    { --  1       2       3       4       5       6       7       8
      { "A", _a_, "…", _at, "Ê", "ê", "Ş", "ş" },
      { "შ", _s_, "$", "4", "Ë", "ë", "İ", "ı" },
      { "D", "დ", "%", "5", "Î", "î", "Ğ", "ğ" },
      { "F", _f_, "^", "6", "Ï", "ï", "Ć", "ć" },
      { "G", _g_, ":", ";", "Ô", "ô", "Č", "č" },
      { "H", _h_, '"', "'", "Œ", "œ", "Đ", "đ" },
      { "ჟ", _j_, "{", "[", "Ù", "ù", "Š", "š" },
      { "K", "კ", "}", "]", "Û", "û", "Ž", "ž" },
      { "L", "ლ", "_", "-", "Ÿ", "ÿ", "Ő", "ő" },
    },
    -- third row
    { --  1       2       3       4       5       6       7       8
      {
        "",
        "",
        "2/2",
        "1/2",
        "",
        "",
        "",
        "",
        width = 1.5,
      },
      { "ძ", _z_, "&", "7", "Á", "á", "Ű", "ű" },
      { "X", _x_, "*", "8", "Ø", "ø", "Ã", "ã" },
      { "ჩ", _c_, "£", "9", "Í", "í", "Þ", "þ" },
      { "V", _v_, "<", com, "Ñ", "ñ", "Ý", "ý" },
      { "B", "ბ", ">", prd, "Ó", "ó", "†", "‡" },
      {
        "N",
        _n_,
        "‘",
        "↑",
        "Ú",
        "ú",
        "–",
        "—",
      },
      {
        "M",
        "მ",
        "’",
        "↓",
        "Ç",
        "ç",
        "…",
        "¨",
      },
      {
        label = "",
        width = 1.5,
        bold = false,
      },
    },
    -- fourth row
    {
      {
        "123",
        "123",
        "აბგ",
        "აბგ",
        "123",
        "123",
        "აბგ",
        "აბგ",
        width = 1.5,
      },
      { label = "🌐" },
      {
        "Äéß",
        "Äéß",
        "Äéß",
        "Äéß",
        "Äéß",
        "Äéß",
        "Äéß",
        "Äéß",
      },
      {
        label = "გამოტოვება",
        " ",
        " ",
        " ",
        " ",
        " ",
        " ",
        " ",
        " ",
        width = 3.0,
      },
      { com, com, "“", "←", "Ũ", "ũ", com, com },
      { prd, prd, "”", "→", "Ĩ", "ĩ", prd, prd },
      {
        label = "⮠",
        "\n",
        "\n",
        "\n",
        "\n",
        "\n",
        "\n",
        "\n",
        "\n",
        width = 1.5,
        bold = true,
      },
    },
  },
}
