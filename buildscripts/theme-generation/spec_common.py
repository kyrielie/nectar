"""Small CSS helpers shared by the spec_themes_*.py design tables."""


def mods(cls, radius="6px", bg="var(--s)", border="1px solid var(--b)", extra=""):
    """Surface treatment for the AO3 blocks (summary, notes, tags) so every theme styles them."""
    return (f".{cls} .summary.module,.{cls} .notes.module,.{cls} .end.notes.module,.{cls} #bodyContainer dl.tags"
            f"{{background:{bg};border:{border};border-radius:{radius};{extra}}}\n"
            f".{cls} #bodyContainer dl.tags{{padding:10px 14px}}\n"
            f".{cls} .notes.module,.{cls} .end.notes.module{{margin:12px 0 0;padding:10px 14px;font-size:calc(var(--u) * 13 * var(--nnw-detail-scale, 1))}}\n"
            f".{cls} .summary.module h3.heading,.{cls} .notes.module h3.heading,.{cls} .end.notes.module h3.heading,.{cls} #bodyContainer dl.tags dt{{color:var(--a)}}\n")


def emph(cls, bold="var(--a)", ital="var(--a)"):
    """Bold and italic text get their own colors."""
    return f".{cls} .articleBody b,.{cls} .articleBody strong{{color:{bold}}}\n.{cls} .articleBody i,.{cls} .articleBody em{{color:{ital}}}\n"


def dropcap(cls, color="var(--a)", font="var(--fh)", size="3em"):
    return (f".{cls} .bd > p:first-of-type::first-letter{{float:left;font-family:{font};font-size:{size};line-height:.82;"
            f"padding:.06em .1em 0 0;color:{color}}}\n")
