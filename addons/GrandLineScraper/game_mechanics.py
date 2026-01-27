import re
import json
from typing import Dict, List, Any, Set
from pathlib import Path
import streamlit as st


KEYWORD_EFFECTS = {
    "Blocker": {
        "description": "When your opponent attacks, rest this card to change the target of the attack to this card.",
        "trigger": "opponent_attack",
        "action": "redirect_attack",
    },
    "Rush": {
        "description": "This card can attack on the turn it is played.",
        "trigger": "on_play",
        "action": "enable_immediate_attack",
    },
    "Double Attack": {
        "description": "This card deals 2 damage instead of 1.",
        "trigger": "damage_dealt",
        "action": "double_damage",
    },
    "Banish": {
        "description": "When a card with Banish deals damage to your opponent's Life, that Life card is trashed instead of added to their hand.",
        "trigger": "life_damage",
        "action": "trash_life_card",
    },
}

TRIGGER_KEYWORDS = {
    "[On Play]": {
        "description": "Activates when this card is played to the field.",
        "timing": "on_play",
    },
    "[When Attacking]": {
        "description": "Activates when this card declares an attack.",
        "timing": "attack_declaration",
    },
    "[On K.O.]": {
        "description": "Activates when this card is K.O.'d (sent from Character area to trash).",
        "timing": "on_ko",
    },
    "[DON!! x1]": {
        "description": "Activates while 1 or more DON!! cards are attached to this card.",
        "timing": "don_attached",
        "don_count": 1,
    },
    "[DON!! x2]": {
        "description": "Activates while 2 or more DON!! cards are attached to this card.",
        "timing": "don_attached",
        "don_count": 2,
    },
    "[End of Your Turn]": {
        "description": "Activates at the end of your turn.",
        "timing": "end_of_turn",
    },
    "[Start of Your Turn]": {
        "description": "Activates at the start of your turn.",
        "timing": "start_of_turn",
    },
    "[Activate: Main]": {
        "description": "Can be activated during your Main Phase.",
        "timing": "main_phase",
        "activation": "manual",
    },
    "[Main]": {
        "description": "Activates during Main Phase.",
        "timing": "main_phase",
    },
    "[Counter]": {
        "description": "Can be activated during the Counter Step to modify the battle.",
        "timing": "counter_step",
    },
    "[Trigger]": {
        "description": "Activates when revealed as a Life card after taking damage.",
        "timing": "life_trigger",
    },
    "[On Block]": {
        "description": "Activates when this card blocks an attack.",
        "timing": "on_block",
    },
    "[Your Turn]": {
        "description": "Active only during your turn.",
        "timing": "your_turn",
        "duration": "continuous",
    },
    "[Opponent's Turn]": {
        "description": "Active only during your opponent's turn.",
        "timing": "opponent_turn",
        "duration": "continuous",
    },
    "[Once Per Turn]": {
        "description": "This effect can only be activated once per turn.",
        "timing": "once_per_turn",
        "limit": 1,
    },
}

GAME_ACTIONS = {
    "draw": {
        "description": "Draw cards from the top of your deck to your hand.",
        "patterns": [r"draw (\d+) card", r"draw a card"],
    },
    "trash": {
        "description": "Send a card to the trash.",
        "patterns": [r"trash (\d+) card", r"trash this card", r"trash a card"],
    },
    "rest": {
        "description": "Turn a card sideways to indicate it has been used.",
        "patterns": [r"rest this card", r"rest (\d+)", r"rest up to"],
    },
    "ko": {
        "description": "Remove a Character from play by sending it to the trash.",
        "patterns": [r"k\.?o\.? (\d+)", r"k\.?o\.? this", r"k\.?o\.? a character"],
    },
    "return_to_hand": {
        "description": "Return a card to its owner's hand.",
        "patterns": [r"return.*to.*hand", r"return to (your|owner's) hand"],
    },
    "return_to_deck": {
        "description": "Return a card to the deck (top or bottom).",
        "patterns": [r"return.*to.*(top|bottom).*deck", r"place.*on (top|bottom) of.*deck"],
    },
    "play": {
        "description": "Put a card onto the field from your hand or another zone.",
        "patterns": [r"play (\d+)", r"play a character", r"play this card"],
    },
    "add_to_hand": {
        "description": "Add a card to your hand from another zone.",
        "patterns": [r"add.*to.*hand", r"add (\d+) card.*to.*hand"],
    },
    "look_at": {
        "description": "Look at cards without revealing them to opponent.",
        "patterns": [r"look at.*(top|bottom) (\d+)", r"look at.*deck"],
    },
    "reveal": {
        "description": "Show a card to both players.",
        "patterns": [r"reveal (\d+)", r"reveal a card", r"reveal.*from"],
    },
    "attach_don": {
        "description": "Attach DON!! cards to a Leader or Character.",
        "patterns": [r"attach.*don", r"add.*don.*to"],
    },
    "power_boost": {
        "description": "Increase a card's power temporarily or permanently.",
        "patterns": [r"\+(\d+)", r"gains? (\d+) power", r"power \+(\d+)"],
    },
    "power_reduce": {
        "description": "Decrease a card's power.",
        "patterns": [r"-(\d+)", r"loses? (\d+) power", r"power -(\d+)", r"gets? -(\d+)"],
    },
    "cost_reduce": {
        "description": "Reduce the cost to play a card.",
        "patterns": [r"cost -(\d+)", r"reduce.*cost.*by (\d+)", r"costs? (\d+) less"],
    },
    "cannot_attack": {
        "description": "Prevent a card from attacking.",
        "patterns": [r"cannot attack", r"can't attack"],
    },
    "cannot_block": {
        "description": "Prevent a card from blocking.",
        "patterns": [r"cannot block", r"can't block"],
    },
    "cannot_be_ko": {
        "description": "Prevent a card from being K.O.'d.",
        "patterns": [r"cannot be k\.?o\.?", r"can't be k\.?o\.?"],
    },
    "search_deck": {
        "description": "Look through your deck for specific cards.",
        "patterns": [r"search.*deck", r"look at.*deck.*add"],
    },
    "give_keyword": {
        "description": "Grant a keyword effect to a card.",
        "patterns": [r"gains? (blocker|rush|double attack|banish)", r"give.*this.*(blocker|rush)"],
    },
    "life_damage": {
        "description": "Deal damage to the opponent's Life cards.",
        "patterns": [r"deal (\d+) damage.*life", r"damage.*to.*life"],
    },
    "trash_from_hand": {
        "description": "Discard cards from hand to trash.",
        "patterns": [r"trash.*from.*hand", r"discard (\d+)"],
    },
}

CARD_ZONES = {
    "hand": "Cards in your hand",
    "deck": "Cards in your deck",
    "trash": "Cards in your trash/discard pile",
    "life": "Face-down Life cards",
    "field": "Leader area, Character area, Stage area, and Cost area",
    "character_area": "Area where Character cards are played",
    "leader_area": "Area where your Leader card is placed",
    "stage_area": "Area where Stage cards are played",
    "cost_area": "Area where DON!! cards are placed for paying costs",
    "don_deck": "Deck containing your 10 DON!! cards",
}

CARD_STATES = {
    "active": "Card is upright and ready to be used",
    "rested": "Card is turned sideways, indicating it has been used",
    "attached": "DON!! cards attached to a Leader or Character",
    "face_down": "Card is not visible (Life cards)",
    "face_up": "Card is visible to both players",
}

TURN_PHASES = {
    "refresh_phase": "Set all rested cards to active, add DON!! from DON!! deck to cost area",
    "draw_phase": "Draw 1 card from your deck",
    "don_phase": "Add DON!! cards from your DON!! deck to your cost area",
    "main_phase": "Play Characters, Stages, Events, attach DON!!, and attack",
    "end_phase": "End your turn effects trigger, then pass to opponent",
}

BATTLE_STEPS = {
    "attack_declaration": "Declare which card is attacking and the target",
    "counter_step": "Defender can play Counter events and use Counter abilities",
    "damage_step": "Compare power and deal damage if attack is successful",
    "battle_resolution": "Determine winner and apply effects",
}


class GameMechanicsExtractor:
    def __init__(self):
        self.keyword_effects = KEYWORD_EFFECTS
        self.trigger_keywords = TRIGGER_KEYWORDS
        self.game_actions = GAME_ACTIONS
        self.card_zones = CARD_ZONES
        self.card_states = CARD_STATES
        self.turn_phases = TURN_PHASES
        self.battle_steps = BATTLE_STEPS
    
    def extract_mechanics_from_cards(self, cards: List[Dict[str, Any]]) -> Dict[str, Any]:
        """Extract all game mechanics from card effect text"""
        
        found_keywords: Dict[str, List[str]] = {}
        found_triggers: Dict[str, List[str]] = {}
        found_actions: Dict[str, List[str]] = {}
        unique_effect_patterns: Set[str] = set()
        
        for card in cards:
            effect = card.get('effect', '') or card.get('effect_english', '') or ''
            card_id = card.get('id', '') or card.get('card_code', '')
            card_name = card.get('name', '')
            
            if not effect:
                continue
            
            for keyword, info in self.keyword_effects.items():
                if keyword.lower() in effect.lower():
                    if keyword not in found_keywords:
                        found_keywords[keyword] = []
                    found_keywords[keyword].append(f"{card_id} ({card_name})")
            
            for trigger, info in self.trigger_keywords.items():
                if trigger.lower() in effect.lower():
                    if trigger not in found_triggers:
                        found_triggers[trigger] = []
                    found_triggers[trigger].append(f"{card_id} ({card_name})")
            
            for action, info in self.game_actions.items():
                for pattern in info['patterns']:
                    if re.search(pattern, effect, re.IGNORECASE):
                        if action not in found_actions:
                            found_actions[action] = []
                        card_ref = f"{card_id} ({card_name})"
                        if card_ref not in found_actions[action]:
                            found_actions[action].append(card_ref)
                        break
            
            effect_lower = effect.lower().strip()
            if effect_lower:
                unique_effect_patterns.add(effect_lower[:100])
        
        return {
            "keyword_effects": {
                "definitions": self.keyword_effects,
                "cards_with_keyword": {k: len(v) for k, v in found_keywords.items()},
                "sample_cards": {k: v[:5] for k, v in found_keywords.items()},
            },
            "trigger_keywords": {
                "definitions": self.trigger_keywords,
                "cards_with_trigger": {k: len(v) for k, v in found_triggers.items()},
                "sample_cards": {k: v[:5] for k, v in found_triggers.items()},
            },
            "game_actions": {
                "definitions": {k: v['description'] for k, v in self.game_actions.items()},
                "cards_with_action": {k: len(v) for k, v in found_actions.items()},
                "sample_cards": {k: v[:5] for k, v in found_actions.items()},
            },
            "card_zones": self.card_zones,
            "card_states": self.card_states,
            "turn_phases": self.turn_phases,
            "battle_steps": self.battle_steps,
            "statistics": {
                "total_cards_analyzed": len(cards),
                "cards_with_effects": len([c for c in cards if c.get('effect')]),
                "unique_effect_patterns": len(unique_effect_patterns),
            },
        }
    
    def export_mechanics_database(self, cards: List[Dict[str, Any]], output_path: Path) -> str:
        """Export complete game mechanics database to JSON"""
        mechanics = self.extract_mechanics_from_cards(cards)
        
        output_path.parent.mkdir(parents=True, exist_ok=True)
        
        with open(output_path, 'w', encoding='utf-8') as f:
            json.dump(mechanics, f, ensure_ascii=False, indent=2)
        
        st.write(f"✅ Exported game mechanics database with {len(self.keyword_effects)} keywords, {len(self.trigger_keywords)} triggers, {len(self.game_actions)} actions")
        
        return str(output_path)
    
    def get_mechanics_for_dueling(self) -> Dict[str, Any]:
        """Get the core mechanics needed for implementing a dueling system"""
        return {
            "keywords": list(self.keyword_effects.keys()),
            "triggers": list(self.trigger_keywords.keys()),
            "actions": list(self.game_actions.keys()),
            "zones": list(self.card_zones.keys()),
            "states": list(self.card_states.keys()),
            "phases": list(self.turn_phases.keys()),
            "battle_steps": list(self.battle_steps.keys()),
        }
