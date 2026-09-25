## Whether the open document has anything unsaved, expressed as a comparison of history REVISIONS
## rather than of stack depths.
##
## WHAT THE DEPTH COMPARISON GOT WRONG. The shell used to hold `_savedUndoDepth` and call the
## document dirty when `undoCount()` differed from it. Depth is not identity: undo one stroke and
## make a different edit and the stack is the same height it was at the save, so a document with
## genuinely different content read as saved. Reaching the history's capacity did the same thing
## from the other side, by evicting the oldest command and holding the depth still while the
## content moved. `WorldMapEditHistory.currentRevision()` exists precisely so two different
## committed states can never share a number, and this class is the whole of the editor's use of
## it.
##
## NEVER-SAVED IS ITS OWN STATE, not revision zero. A document created by New and a document
## opened from disk and not yet touched both sit at whatever revision their history starts on, so
## a bare revision comparison would call the new one saved and offer to close it without a word.
## The flag is what separates "matches what is on disk" from "has never been on disk".
##
## DOCUMENT SAFETY EXTENDS THIS; IT DOES NOT REPLACE IT. Recovery snapshots, failed writes that
## must not advance the checkpoint, and Save As all need exactly this pair of questions answered
## first.

class_name WorldMapWorkspaceSavePoint
extends RefCounted

var _savedRevision := 0
var _neverSaved := true


## A document that has never been written. Dirty from its first frame -- see the class note.
func beginNewDocument() -> void:
	_savedRevision = 0
	_neverSaved = true


## A document just read from disk, clean at the revision its fresh history starts on.
func beginOpenedDocument(revision: int) -> void:
	_savedRevision = revision
	_neverSaved = false


## Only a write that actually succeeded may call this. A failed save leaving the checkpoint where
## it was is what keeps the document honestly dirty afterwards.
func markSaved(revision: int) -> void:
	_savedRevision = revision
	_neverSaved = false


func isNeverSaved() -> bool:
	return _neverSaved


func savedRevision() -> int:
	return _savedRevision


func isDirty(currentRevision: int) -> bool:
	return _neverSaved or currentRevision != _savedRevision
