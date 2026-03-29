(function() {
	if (window.__inkwellRecapAvatarFallbackInstalled) { return; }
	window.__inkwellRecapAvatarFallbackInstalled = true;

	function isRecapAvatarImage(imageEl) {
		if (!imageEl || imageEl.tagName !== 'IMG') { return false; }
		if (!imageEl.closest) { return false; }
		return !!imageEl.closest('.reading-recap .reading-header h2');
	}

	function replaceWithFallback(imageEl) {
		if (!isRecapAvatarImage(imageEl) || !imageEl.parentNode) { return; }
		if (imageEl.dataset.inkwellAvatarFallbackApplied === 'true') { return; }
		imageEl.dataset.inkwellAvatarFallbackApplied = 'true';
		var fallbackEl = document.createElement('span');
		fallbackEl.className = 'reading-recap-avatar-fallback';
		fallbackEl.setAttribute('aria-hidden', 'true');
		imageEl.parentNode.replaceChild(fallbackEl, imageEl);
	}

	function updateBrokenRecapAvatars() {
		var imageEls = document.querySelectorAll('.reading-recap .reading-header h2 img');
		for (var i = 0; i < imageEls.length; i++) {
			var imageEl = imageEls[i];
			if (imageEl.complete && imageEl.naturalWidth === 0) {
				replaceWithFallback(imageEl);
			}
		}
	}

	document.addEventListener('error', function(event) {
		replaceWithFallback(event.target);
	}, true);
	document.addEventListener('DOMContentLoaded', updateBrokenRecapAvatars);
	window.addEventListener('load', updateBrokenRecapAvatars);
})();
