extends Resource
class_name CosmeticItem
## Data-only description of one purchasable cosmetic. One .tres per item
## lives under resources/economy/cosmetic_items/ — adding a new cosmetic
## later is "add a file," not a code change, per the project's
## resource-driven-systems standard.

enum Category { VESSEL, TRAIL, MOON, UI_THEME, SOUND }

@export var id: String = ""
@export var display_name: String = ""
@export var category: Category = Category.VESSEL
@export var cost: int = 0
@export_multiline var description: String = ""
