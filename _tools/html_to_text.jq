# MyMiniFactory serves a model's blurb twice: "description" is plain text with
# every line break already stripped, and "description_html" is the version the
# creator actually wrote. Taking the plain field turns a formatted listing --
# paragraphs, "Set includes:" lists -- into one unbroken wall of text.
#
# This rebuilds readable text from the HTML. Block tags become line breaks,
# list items become dashes, inline tags and entities are resolved.
def html_to_text:
  # Carriage returns first. The HTML arrives with \r\n endings, and leaving the
  # \r in place means the blank-line collapse below never matches: "\r\n\r\n\r\n"
  # is not a run of newlines as far as the regex is concerned.
    gsub("\r"; "")
  | gsub("(?i)<br[ \\t]*/?>"; "\n")
  | gsub("(?i)</p[ \\t]*>"; "\n\n")
  | gsub("(?i)</li[ \\t]*>"; "\n")
  | gsub("(?i)<li[^>]*>"; "- ")
  | gsub("(?i)</(h[1-6]|div|tr|ul|ol|blockquote)[ \\t]*>"; "\n\n")
  | gsub("<[^>]*>"; "")
  # entities, including the non-breaking spaces MMF sprinkles everywhere
  | gsub("&nbsp;"; " ")
  | gsub("&#160;"; " ")
  | gsub("\u00a0"; " ")
  | gsub("&lt;"; "<")
  | gsub("&gt;"; ">")
  | gsub("&quot;"; "\"")
  | gsub("&#39;"; "'")
  | gsub("&apos;"; "'")
  | gsub("&amp;"; "&")          # last, so &amp;lt; does not become <
  # tidy: no trailing spaces, no runs of blank lines, no leading/trailing space
  | gsub("[ \\t]+"; " ")
  | gsub(" +\n"; "\n")
  | gsub("\n +"; "\n")
  | gsub("\n{3,}"; "\n\n")
  | sub("^[ \\t\n]+"; "")
  | sub("[ \\t\n]+$"; "");

# Prefer the creator's formatting; fall back to the flat field when there is no
# HTML, and never return something emptier than what we started with.
def best_description:
  (.description_html // "") as $html
  | (.description // "") as $plain
  | if ($html | length) > 0
    then ($html | html_to_text) as $t
         | if ($t | length) > 0 then $t else $plain end
    else $plain
    end;

best_description
