class_name Map

## The unique identifier or name of the map
var name: String

## The dimensions of the map grid
var boardSize: Vector2i

## Array of strings representing the grid (e.g. "." for clear, "T" for obstacles, "W" for water/abyss)
var layout: Array

## Versioned map data used by replay compatibility checks.
var revision: int = 1

## Integer surface elevation matrix, indexed as heights[y][x].
var heights: Array = []
