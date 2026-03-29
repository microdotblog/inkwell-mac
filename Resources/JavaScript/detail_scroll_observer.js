(function() {
	if (window.__inkwellScrollObserverInstalled) { return; }
	window.__inkwellScrollObserverInstalled = true;

	function currentScrollTop() {
		if (typeof window.scrollY === 'number') { return window.scrollY; }
		if (document.documentElement && typeof document.documentElement.scrollTop === 'number') { return document.documentElement.scrollTop; }
		if (document.body && typeof document.body.scrollTop === 'number') { return document.body.scrollTop; }
		return 0;
	}

	function postScrollState() {
		window.webkit.messageHandlers.scrollChanged.postMessage(currentScrollTop() > 1);
	}

	window.addEventListener('scroll', postScrollState, { passive: true });
	window.addEventListener('load', postScrollState);
	postScrollState();
})();
