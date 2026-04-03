(function() {
	if (window.__inkwellImageClickObserverInstalled) { return; }
	window.__inkwellImageClickObserverInstalled = true;

	function absoluteURL(urlValue) {
		var rawValue = String(urlValue || '').trim();
		if (!rawValue) { return ''; }
		try {
			return new URL(rawValue, document.baseURI).toString();
		}
		catch (error) {
			return '';
		}
	}

	function isPlainPrimaryClick(event) {
		if (!event) { return false; }
		if (event.defaultPrevented) { return false; }
		if (typeof event.button === 'number' && event.button !== 0) { return false; }
		return !event.metaKey && !event.ctrlKey && !event.shiftKey && !event.altKey;
	}

	function imageLikeURL(urlValue) {
		var absoluteValue = absoluteURL(urlValue);
		if (!absoluteValue) { return ''; }
		try {
			var parsedURL = new URL(absoluteValue);
			if (/\.(apng|avif|bmp|gif|heic|heif|jpe?g|png|svg|tiff?|webp)$/i.test(parsedURL.pathname || '')) {
				return absoluteValue;
			}
		}
		catch (error) {
			return '';
		}
		return '';
	}

	function ignoredImage(imageEl) {
		if (!imageEl || imageEl.tagName !== 'IMG') { return true; }
		if (imageEl.closest && imageEl.closest('.reading-recap .reading-header h2')) { return true; }
		return false;
	}

	document.addEventListener('click', function(event) {
		if (!isPlainPrimaryClick(event)) { return; }
		if (!event.target || !event.target.closest) { return; }

		var imageEl = event.target.closest('img');
		if (ignoredImage(imageEl)) { return; }

		var imageSrc = absoluteURL(imageEl.currentSrc || imageEl.src);
		if (!imageSrc) { return; }

		var linkEl = imageEl.closest('a[href]');
		var anchorHref = linkEl ? absoluteURL(linkEl.getAttribute('href')) : '';
		var imageURL = imageLikeURL(anchorHref) || imageSrc;

		if (!window.webkit || !window.webkit.messageHandlers || !window.webkit.messageHandlers.imageClicked) {
			return;
		}

		window.webkit.messageHandlers.imageClicked.postMessage({
			image_url: imageURL,
			image_src: imageSrc,
			anchor_href: anchorHref
		});
		event.preventDefault();
		event.stopPropagation();
	}, true);
})();
