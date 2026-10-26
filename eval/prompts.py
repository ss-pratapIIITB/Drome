"""Question definitions and keyword guard used by the local evaluation harness.

The baseline question text and the keyword lists mirror the shipping app:

- ``Drome/AI/LayaMLXRuntime.swift`` (``unsafeQuestion``, ``categoryQuestion``)
- ``Drome/AI/AIContentFilter.swift`` (``classifyWithHeuristics``)

Keep these in sync when the app changes. The variants exist only for evaluation.
"""

from __future__ import annotations

from typing import Any

CATEGORY_CRITERIA = {
    "safe": "neutral, educational, entertaining, practical, or ordinary content",
    "violence": "violence, death, crime, war, terrorism, or disaster",
    "self_harm": "suicide, self-harm, overdose, or severe mental-health crisis",
    "adult": "nudity, pornography, or explicit sexual content",
    "health_crisis": "alarming disease, outbreak, injury, or medical emergency",
    "financial_stress": "recession, layoffs, bankruptcy, or financial doom",
    "urgency": "high-pressure demand, fear-inducing warning, or act-now language",
    "outrage": "rage bait, scandal, inflammatory claim, or alarming statistic",
}

BASELINE_INSTRUCTION = (
    "Would this web content likely trigger anxiety or be unsafe because it contains "
    "violence, death, self-harm, crime, disaster, a health crisis, financial doom, "
    "adult content, outrage bait, alarming claims, or high-pressure urgency?"
)

# The app prepends page context (title + host) to each block before
# classification; this keeps legitimate news from reading as "unsafe" while
# leaving the question wording unchanged.
SHIPPING_INSTRUCTION = BASELINE_INSTRUCTION

VARIANTS: dict[str, dict[str, Any]] = {
    "baseline": {
        "unsafe": BASELINE_INSTRUCTION,
        "state": "plain",
    },
    "reporting_aware": {
        "unsafe": (
            "Would a typical reader find this block anxiety-inducing or unsafe in isolation? "
            "Judge the block itself, not the topic. Factual news reporting that mentions "
            "violence, death, or disaster is safe unless the block is graphic, sensational, "
            "or focused on disturbing detail. Flag graphic violence, self-harm ideation or "
            "instructions, explicit sexual content, alarming health claims, financial doom, "
            "high-pressure urgency, and outrage bait."
        ),
        "state": "plain",
    },
    "reader_impact": {
        "unsafe": (
            "If this block appeared alone in a calm reading feed, would it make a typical "
            "reader feel anxious or unsafe? Consider graphic violence, self-harm, explicit "
            "sexual content, alarming health claims, financial doom, high-pressure urgency, "
            "or outrage bait. Factual, educational, or analytical discussion is safe."
        ),
        "state": "plain",
    },
    "strict_graphic": {
        "unsafe": (
            "Does this block contain graphic violence, self-harm ideation or instructions, "
            "explicit sexual content, a terrifying health claim, financial doom, a "
            "high-pressure threat, or outrage bait? Factual reporting, education, and "
            "ordinary mentions of these topics are safe."
        ),
        "state": "plain",
    },
    "with_examples": {
        "unsafe": (
            "Would a typical reader find this block anxiety-inducing or unsafe? Flag graphic "
            "violence, self-harm ideation or instructions, explicit sexual content, alarming "
            "health claims, financial doom, high-pressure urgency, and outrage bait. Examples: "
            "an estimate of earthquake damage is safe; a description of burned bodies is unsafe. "
            "A factual report on homicide rates is safe; a threat to kill someone is unsafe."
        ),
        "state": "plain",
    },
    "short": {
        "unsafe": "Is this block unsafe or anxiety-inducing for a reader?",
        "state": "plain",
    },
    "field_block": {
        "unsafe": (
            "Would a typical reader find `block` anxiety-inducing or unsafe in isolation? "
            "Judge `block` itself, not the topic. Factual news reporting that mentions "
            "violence, death, or disaster is safe unless the block is graphic, sensational, "
            "or focused on disturbing detail."
        ),
        "state": "block",
    },
    "field_block_plain": {
        "unsafe": (
            "Would a typical reader find `block` anxiety-inducing or unsafe in isolation? "
            "Judge `block` itself, not the topic. Factual news reporting that mentions "
            "violence, death, or disaster is safe unless the block is graphic, sensational, "
            "or focused on disturbing detail."
        ),
        "state": "plain",
    },
    "compact_reporting": {
        "unsafe": (
            "Would a typical reader find this block anxiety-inducing or unsafe? Judge the "
            "block, not the topic. Factual reporting is safe unless it is graphic, "
            "sensational, or focused on disturbing detail."
        ),
        "state": "plain",
    },
    "compact_flag": {
        "unsafe": (
            "Does this block contain graphic or anxiety-inducing content a reader would want "
            "hidden? Factual reporting and ordinary mentions are safe."
        ),
        "state": "plain",
    },
    "outrage_aware": {
        "unsafe": (
            "Would a typical reader find this block anxiety-inducing or unsafe? Flag graphic "
            "violence, self-harm, explicit sexual content, alarming health claims, financial "
            "doom, high-pressure urgency, and rage bait or inflammatory headlines designed to "
            "make people angry. Factual reporting is safe unless graphic or sensational."
        ),
        "state": "plain",
    },
    "outrage_compact": {
        "unsafe": (
            "Would a typical reader find this block anxiety-inducing or unsafe? Flag graphic "
            "violence, self-harm, explicit content, health scares, financial doom, pressure "
            "tactics, and rage bait. Factual reporting is safe."
        ),
        "state": "plain",
    },
}


def questions_for(variant: str) -> dict[str, dict[str, Any]]:
    spec = VARIANTS[variant]
    return {
        "unsafe": {
            "type": "noul",
            "instructions": spec["unsafe"],
        },
        "category": {
            "type": "choice",
            "instructions": "Which content-safety category best describes this web content?",
            "criteria": CATEGORY_CRITERIA,
        },
    }


def state_for(variant: str, text: str) -> Any:
    if VARIANTS[variant]["state"] == "block":
        return {"block": text}
    return text


HIGH_RISK: list[tuple[str, str]] = [
    ("killed", "Violence/death"),
    ("murder", "Violence"),
    ("shooting", "Violence"),
    ("bombing", "Violence"),
    ("massacre", "Violence"),
    ("suicide", "Self-harm"),
    ("overdose", "Self-harm"),
    ("terrorist", "Terrorism"),
    ("horrifying", "Fear-inducing"),
    ("terrifying", "Fear-inducing"),
    ("devastating", "Alarming"),
    ("death toll", "Disaster"),
    ("nude", "Adult content"),
    ("naked", "Adult content"),
    ("nsfw", "Adult content"),
    ("porn", "Adult content"),
    ("sex tape", "Adult content"),
    ("leaked photos", "Privacy violation"),
    ("explicit", "Adult content"),
    ("onlyfans", "Adult content"),
    ("dead body", "Violence/death"),
    ("bodies found", "Violence/death"),
]

MEDIUM_RISK: list[tuple[str, str]] = [
    ("breaking news", "Breaking news"),
    ("crisis", "Crisis"),
    ("disaster", "Disaster"),
    ("pandemic", "Health crisis"),
    ("outbreak", "Health crisis"),
    ("recession", "Financial stress"),
    ("inflation", "Financial stress"),
    ("layoffs", "Job insecurity"),
    ("scandal", "Scandal"),
    ("outrage", "Outrage bait"),
    ("shocking", "Alarming"),
    ("act now", "Urgency pressure"),
    ("war", "Conflict"),
    ("arrested", "Crime"),
    ("sexual", "Adult content"),
    ("strip", "Adult content"),
]


def keyword_classify(text: str) -> tuple[bool, str, int]:
    """Return (is_safe, reason, score), matching AIContentFilter.swift."""
    lower = text.lower()
    score = 0
    reasons: list[str] = []
    for phrase, reason in HIGH_RISK:
        if phrase in lower:
            score += 2
            reasons.append(reason)
    for phrase, reason in MEDIUM_RISK:
        if phrase in lower:
            score += 1
            reasons.append(reason)

    threshold = 2 if len(text) > 100 else 3
    if score >= threshold:
        return False, " · ".join(reasons[:2]), score
    return True, "Safe content", score
