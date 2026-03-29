(function() {
	if (window.__inkwellSelectionObserverInstalled) { return; }
	window.__inkwellSelectionObserverInstalled = true;

	function postSelectionState() {
		var selection = window.getSelection();
		var hasSelection = false;
		if (selection && !selection.isCollapsed && selection.rangeCount > 0 && selection.toString().trim().length > 0) {
			var content = document.querySelector('.post-content');
			if (content) {
				var range = selection.getRangeAt(0);
				hasSelection = content.contains(range.commonAncestorContainer);
			}
		}
		window.webkit.messageHandlers.selectionChanged.postMessage(hasSelection);
	}

	document.addEventListener('selectionchange', postSelectionState);
	document.addEventListener('mouseup', postSelectionState);
	document.addEventListener('keyup', postSelectionState);
	window.addEventListener('load', postSelectionState);
	postSelectionState();
})();
