(function() {
	if (window.__inkwellLinkHoverObserverInstalled) { return; }
	window.__inkwellLinkHoverObserverInstalled = true;

	var currentHref = '';

	function closestLink(node) {
		while (node) {
			if (node.nodeType === 1) {
				if (node.matches && node.matches('a[href]')) { return node; }
				if (node.closest) {
					var found = node.closest('a[href]');
					if (found) { return found; }
				}
			}
			node = node.parentNode;
		}
		return null;
	}

	function hrefForLink(link) {
		if (!link) { return ''; }
		try {
			return link.href || '';
		}
		catch (e) {
			return '';
		}
	}

	function postHref(href) {
		var nextHref = (href || '').trim();
		if (nextHref === currentHref) { return; }
		currentHref = nextHref;
		window.webkit.messageHandlers.linkHover.postMessage(nextHref);
	}

	document.addEventListener('mouseover', function(event) {
		postHref(hrefForLink(closestLink(event.target)));
	}, true);

	document.addEventListener('mouseout', function(event) {
		var fromLink = closestLink(event.target);
		var toLink = closestLink(event.relatedTarget);
		if (fromLink && toLink && fromLink === toLink) { return; }
		postHref(hrefForLink(toLink));
	}, true);

	window.addEventListener('blur', function() { postHref(''); });
	window.addEventListener('pagehide', function() { postHref(''); });
	window.addEventListener('load', function() { postHref(''); });
	postHref('');
})();
