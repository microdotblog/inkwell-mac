(function() {
	if (window.inkwellDetail) { return; }

	function stringValue(value) {
		if (value == null) { return ''; }
		return String(value);
	}

	function currentScrollTop() {
		if (typeof window.scrollY === 'number') { return window.scrollY; }
		if (document.documentElement && typeof document.documentElement.scrollTop === 'number') { return document.documentElement.scrollTop; }
		if (document.body && typeof document.body.scrollTop === 'number') { return document.body.scrollTop; }
		return 0;
	}

	function maxScrollTop() {
		var bodyHeight = document.body ? document.body.scrollHeight : 0;
		var docHeight = document.documentElement ? document.documentElement.scrollHeight : 0;
		return Math.max(0, Math.max(bodyHeight, docHeight) - window.innerHeight);
	}

	function normalizeRecapColor(rawColor) {
		var normalizedColor = stringValue(rawColor).trim();
		if (!normalizedColor) { return ''; }
		if (!/^#([0-9a-f]{3}|[0-9a-f]{4}|[0-9a-f]{6}|[0-9a-f]{8})$/i.test(normalizedColor)) { return ''; }
		var hex = normalizedColor.slice(1);
		if (hex.length === 3 || hex.length === 4) {
			var expanded = '';
			for (var i = 0; i < hex.length; i++) {
				expanded += hex.charAt(i) + hex.charAt(i);
			}
			return '#' + expanded;
		}
		return '#' + hex;
	}

	function withRecapColorOpacity(colorValue, opacityHex) {
		var normalizedColor = normalizeRecapColor(colorValue);
		if (!normalizedColor) { return ''; }
		var baseColor = normalizedColor.length === 9 ? normalizedColor.slice(0, 7) : normalizedColor;
		var normalizedOpacity = stringValue(opacityHex || '80').trim().toLowerCase();
		var safeOpacity = /^[0-9a-f]{2}$/i.test(normalizedOpacity) ? normalizedOpacity : '80';
		return baseColor + safeOpacity;
	}

	window.inkwellDetail = {
		getSelectionPayload: function() {
			return (window.inkwellHighlights && window.inkwellHighlights.getSelectionPayload) ? window.inkwellHighlights.getSelectionPayload() : null;
		},

		clearSelection: function() {
			if (window.inkwellHighlights && window.inkwellHighlights.clearSelection) {
				window.inkwellHighlights.clearSelection();
			}
		},

		restoreHighlights: function(payload) {
			if (window.inkwellHighlights && window.inkwellHighlights.restoreHighlights) {
				window.inkwellHighlights.restoreHighlights(Array.isArray(payload) ? payload : []);
			}
		},

		applyPreferredTextSettings: function(payload) {
			payload = payload || {};

			var bg = stringValue(payload.background_hex);
			var font = stringValue(payload.font_css);
			var text = stringValue(payload.text_color);
			var link = stringValue(payload.link_color);
			var quote = stringValue(payload.quote_color);
			var quoteBorder = stringValue(payload.quote_border_color);
			var readerHighlightBg = stringValue(payload.reader_highlight_background);
			var contentSize = Number(payload.content_font_size) || 0;
			var titleSize = Number(payload.title_font_size) || contentSize;
			var body = document.body;
			if (!body) { return; }

			document.documentElement.style.setProperty('--reader-highlight-background', readerHighlightBg);
			document.documentElement.style.backgroundColor = bg;
			document.documentElement.style.color = text;
			body.style.backgroundColor = bg;
			body.style.color = text;
			body.style.fontFamily = font;
			body.style.fontSize = contentSize + 'px';

			var content = document.querySelector('.content');
			if (content) {
				content.style.fontFamily = font;
				content.style.fontSize = contentSize + 'px';
			}

			var titleNodes = document.querySelectorAll('.post-title');
			for (var t = 0; t < titleNodes.length; t++) {
				titleNodes[t].style.fontFamily = font;
				titleNodes[t].style.fontSize = titleSize + 'px';
				titleNodes[t].style.color = text;
			}

			var nodes = document.querySelectorAll('.post-content,p,li,td,th,pre,blockquote');
			for (var i = 0; i < nodes.length; i++) {
				var node = nodes[i];
				node.style.fontFamily = font;
				node.style.fontSize = contentSize + 'px';
				if (node.closest && node.closest('.reading-recap')) { continue; }
				node.style.color = text;
			}

			var links = document.querySelectorAll('a');
			for (var j = 0; j < links.length; j++) {
				links[j].style.color = link;
			}

			var quotes = document.querySelectorAll('blockquote');
			for (var k = 0; k < quotes.length; k++) {
				if (quotes[k].closest && quotes[k].closest('.reading-recap')) { continue; }
				quotes[k].style.color = quote;
				quotes[k].style.borderLeftColor = quoteBorder;
			}
		},

		applyReadingRecapColors: function(payload) {
			payload = payload || {};

			var isDarkTheme = !!payload.is_dark_theme;
			var recapEls = document.querySelectorAll('.reading-recap');
			for (var index = 0; index < recapEls.length; index++) {
				var recapEl = recapEls[index];
				var lightColor = normalizeRecapColor(recapEl.dataset.colorLight);
				var darkColor = normalizeRecapColor(recapEl.dataset.colorDark || recapEl.dataset.colorRight);
				var recapBaseColor = isDarkTheme ? (darkColor || lightColor) : (lightColor || darkColor);
				var recapColor = withRecapColorOpacity(recapBaseColor, '80');
				var recapTopicsColor = withRecapColorOpacity(recapBaseColor, 'e6');
				var recapBlockquoteBackground = withRecapColorOpacity(recapBaseColor, '99');
				var recapBlockquoteBorder = withRecapColorOpacity(recapBaseColor, 'ff');

				recapEl.style.backgroundColor = recapColor || '';
				if (recapTopicsColor) {
					recapEl.style.setProperty('--recap-topics-background', recapTopicsColor);
				}
				else {
					recapEl.style.removeProperty('--recap-topics-background');
				}

				if (recapBlockquoteBackground) {
					recapEl.style.setProperty('--recap-blockquote-background', recapBlockquoteBackground);
				}
				else {
					recapEl.style.removeProperty('--recap-blockquote-background');
				}

				if (recapBlockquoteBorder) {
					recapEl.style.setProperty('--recap-blockquote-border', recapBlockquoteBorder);
				}
				else {
					recapEl.style.removeProperty('--recap-blockquote-border');
				}
			}
		},

		scrollReadingRecap: function(payload) {
			payload = payload || {};

			var isForward = !!payload.is_forward;
			var scrollInset = Number(payload.scroll_inset);
			if (!isFinite(scrollInset)) {
				scrollInset = 0;
			}

			function smoothScrollTo(targetTop) {
				var adjustedTop = targetTop - scrollInset;
				var clampedTop = Math.max(0, Math.min(maxScrollTop(), adjustedTop));
				window.scrollTo({ top: clampedTop, behavior: 'smooth' });
			}

			function fallbackScroll(forward) {
				var pageStep = Math.max(window.innerHeight * 0.9, 120);
				var top = currentScrollTop();
				var fallbackTop = forward ? (top + pageStep) : (top - pageStep);
				window.scrollTo({ top: Math.max(0, Math.min(maxScrollTop(), fallbackTop)), behavior: 'smooth' });
			}

			var recapEls = document.querySelectorAll('.reading-recap');
			if (!recapEls || recapEls.length === 0) {
				fallbackScroll(isForward);
				return;
			}

			var top = currentScrollTop();
			var currentVisibleTop = top + scrollInset;
			var threshold = Math.max(window.innerHeight * 0.08, 24);
			var recapTops = [];
			for (var index = 0; index < recapEls.length; index++) {
				var recapEl = recapEls[index];
				var rect = recapEl.getBoundingClientRect();
				recapTops.push(rect.top + top);
			}

			if (isForward) {
				for (var nextIndex = 0; nextIndex < recapTops.length; nextIndex++) {
					if (recapTops[nextIndex] > currentVisibleTop + threshold) {
						smoothScrollTo(recapTops[nextIndex]);
						return;
					}
				}

				fallbackScroll(true);
				return;
			}

			for (var previousIndex = recapTops.length - 1; previousIndex >= 0; previousIndex--) {
				if (recapTops[previousIndex] < currentVisibleTop - threshold) {
					smoothScrollTo(recapTops[previousIndex]);
					return;
				}
			}

			fallbackScroll(false);
		}
	};
})();
