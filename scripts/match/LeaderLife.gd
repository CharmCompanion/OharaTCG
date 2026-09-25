# res://scripts/match/LeaderLife.gd
# Leader cards hard-set each player's starting Life total. The punk-records
# data does NOT carry the printed Life value, so we keep a curated table of
# every leader whose Life deviates from the dominant default of 5.
# Source: https://onepiececardlist.com/leaders (138 leaders table, fetched 2026-09-18).
# Everything not listed here defaults to Life 5.
# If a future import adds a "life" field to the leader's card dict, the
# engine reads that FIRST and this table is only a fallback.

class_name MtLeaderLife

extends RefCounted

const DEFAULT_LIFE := 5

const OVERRIDES := {
	"EB01-001": 4, "EB01-021": 4, "EB01-040": 4, "EB02-010": 4,
	"EB03-001": 4, "EB04-001": 4,
	"OP01-002": 4, "OP01-003": 4, "OP01-061": 4, "OP01-062": 4,
	"OP02-001": 6, "OP02-002": 4, "OP02-026": 4, "OP02-072": 4,
	"OP03-022": 4, "OP03-077": 4,
	"OP04-019": 4, "OP04-020": 4, "OP04-040": 4, "OP04-058": 4,
	"OP05-001": 4, "OP05-002": 4, "OP05-022": 4, "OP05-041": 4, "OP05-098": 4,
	"OP06-001": 4, "OP06-021": 4, "OP06-022": 4, "OP06-042": 4,
	"OP07-097": 2,
	"OP08-002": 4, "OP08-057": 4, "OP08-058": 4,
	"OP09-022": 4, "OP09-061": 4, "OP09-062": 4,
	"OP10-001": 4, "OP10-002": 4, "OP10-003": 4, "OP10-022": 4, "OP10-042": 4,
	"OP11-001": 4, "OP11-022": 4, "OP11-040": 3, "OP11-041": 4,
	"OP12-041": 4, "OP12-061": 4, "OP12-081": 4,
	"OP13-001": 4, "OP13-002": 3, "OP13-079": 4,
	"OP14-041": 4, "OP14-080": 4,
	"OP15-001": 4, "OP15-002": 4, "OP15-022": 4,
	"OP16-022": 4, "OP16-080": 4,
	"ST10-001": 4, "ST10-002": 3,
	"ST12-001": 4,
	"ST13-001": 4, "ST13-002": 4, "ST13-003": 4,
	"ST29-001": 6,
	"ST30-001": 4,
}

static func value(card_code: String) -> int:
	var code := card_code.strip_edges().split("/", false)[0]
	if OVERRIDES.has(code):
		return int(OVERRIDES[code])
	return DEFAULT_LIFE