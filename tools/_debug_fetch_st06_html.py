import re
from urllib.request import Request, urlopen


def main() -> None:
    url = "https://en.onepiece-cardgame.com/products/decks/st06.php"
    req = Request(url, headers={"User-Agent": "Mozilla/5.0"})
    html = urlopen(req, timeout=30).read().decode("utf-8", "replace")

    print("len", len(html))

    needles = [
        "deck",
        "recipe",
        "cardlist",
        "st06",
        "ST06",
        "quantity",
        "qty",
        "count",
        "copies",
        "data-json",
        "application/ld+json",
        "application/json",
    ]
    for n in needles:
        print(f"{n}: {html.lower().count(n.lower())}")

    scripts = re.findall(r"<script[^>]+src=\"([^\"]+)\"", html, flags=re.I)
    print("script src count", len(scripts))
    for s in scripts:
        if any(k in s.lower() for k in ["deck", "card", "product", "st06", "json"]):
            print("script:", s)

    # Look for obvious JSON blobs
    jsonish = re.findall(r"\{[^{}]{0,500}\}", html, flags=re.S)
    print("json-ish small objects", len(jsonish))

    # Find card code mentions
    codes = sorted(set(re.findall(r"st06-\d{3}", html, flags=re.I)))
    print("codes found", len(codes))
    if codes:
        print("first few codes", codes[:30])
        first = codes[0]
        idx = html.lower().find(first.lower())
        if idx != -1:
            snippet = html[max(0, idx - 200) : idx + 400]
            snippet = re.sub(r"\s+", " ", snippet)
            print("context:", snippet[:600])


if __name__ == "__main__":
    main()
