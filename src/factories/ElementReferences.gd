class_name ElementReferences

const STANDARD: Array[String] = [
	"fire",
	"ice",
	"wood",
	"steel",
	"darkness",
	"light",
	"earth",
	"water",
	"thunder",
	"wind",
	"none"
]


static func isValid(element: String) -> bool:
	return STANDARD.has(element.to_lower())
