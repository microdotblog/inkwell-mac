var MicroEditor = (function () {
	let isDebugging = false;
	let isIgnoringInput = false;
	let isSelectAll = false;
	let isNextButtonDisable = false;
	let isShowingChars = true;
	let isLastCharEnter = false;
	let hasFinishedSetup = false;
	let textBoxID = "";
	let textPreviewID = "";
	let toolbarID = "";
	let uploadPhotoHandler = null;
	let uploadRecorderHandler = null;
	let backButtonHandler = null;
	let backButtonTitle = "";
	let sendDraftHandler = null;
	let sendPostHandler = null;
	let sendPostTitle = "";
	let saveHandler = null;
	let contentChangeHandler = null;
	let successTimer = null;
	let successFadeTimer = null;
	let isSuccessVisible = false;
	let isSuccessFading = false;
	let undoStack = [{ text: "", selection: null }];
	let redoStack = [];
	let undoTimer = null;
	const undoDelay = 1000;
	const undoMaxSize = 50;
	let autocompleteTimer = null;
	const autocompleteDelay = 500;
	let contentChangeTimer = null;
	const contentChangeDelay = 200;
	let autocompleteHandler = null;
	let dropHandler = null;
	const maxCharsLength = 300;
	const maxBlockquoteLength = 600;
	const editorMarkerSelector = '[data-editor-marker="caret"]';

	function init(config) {
		textBoxID = config.textbox_id;
		textPreviewID = config.preview_id;
		toolbarID = config.toolbar_id;
		uploadPhotoHandler = config.photo_handler;
		uploadRecorderHandler = config.recorder_handler;
		backButtonHandler = config.back_handler;
		backButtonTitle = config.back_button ?? "← Back";
		sendDraftHandler = config.draft_handler;
		sendPostHandler = config.post_handler;
		sendPostTitle = config.post_button ?? "Post";
		saveHandler = config.save_handler;
		contentChangeHandler = config.content_change_handler;
		autocompleteHandler = config.autocomplete_handler;
		dropHandler = config.drop_handler;
		isShowingChars = config.show_chars ?? true;

		setupToolbar();
		setupListeners();
		setupFocus();

		return {
			showProgress: showProgress,
			hideProgress: hideProgress,
			showSuccess: showSuccess,
			hideSuccess: hideSuccess,
			hideCharsRemaining: hideCharsRemaining,
			updateRemaining: updateRemaining,
			replaceUsername: replaceUsername,
			cancelListeners: cancelListeners,
			setText: setText,
			insertLineBreak: insertLineBreak,
			getMarkdown: getMarkdown,
			getHTML: getHTML,
			setPreviewBackground: setPreviewBackground,
			togglePreview: togglePreview
		}
	}

	function debugLog(...args) {
		if (isDebugging) {
			console.log.apply(console, args);
		}
	}

	function setupToolbar() {
		const toolbar = document.getElementById(toolbarID);

		// sometimes this can be called twice? abort if we already have buttons
		let bold_button = document.getElementById(`${textBoxID}_bold_button`);
		if (bold_button && toolbar && toolbar.contains(bold_button)) {
			return;
		}

		// photo button
		if (uploadPhotoHandler) {
			const photo_button = document.createElement('button');
			photo_button.onclick = uploadPhotoHandler;
			photo_button.className = 'editor_toolbar_button editor_photo_button editor_toolbar_margin';
			photo_button.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 50 50" width="20px" height="20px"><path fill="currentColor" d="M 10 11 C 8.343 11 7 12.343 7 14 L 7 36 C 7 37.657 8.343 39 10 39 L 40 39 C 41.657 39 43 37.657 43 36 L 43 14 C 43 12.343 41.657 11 40 11 L 10 11 z M 10 12 L 40 12 C 41.105 12 42 12.895 42 14 L 42 33.091797 L 33.470703 25.421875 C 32.137703 24.223875 30.113203 24.225734 28.783203 25.427734 L 21.851562 31.691406 L 18.533203 28.853516 C 17.219203 27.730516 15.283609 27.733328 13.974609 28.861328 L 8 34.007812 L 8 14 C 8 12.895 8.895 12 10 12 z M 16 17 C 14.343 17 13 18.343 13 20 C 13 21.657 14.343 23 16 23 C 17.657 23 19 21.657 19 20 C 19 18.343 17.657 17 16 17 z"/></svg>';
			toolbar.appendChild(photo_button);
		}

		// recorder button (speaker icon)
		if (uploadRecorderHandler) {
			const recorder_button = document.createElement('button');
			recorder_button.type = 'button';
			recorder_button.className = 'editor_toolbar_button editor_audio_button editor_toolbar_margin';
			recorder_button.title = 'Record or choose audio';
			recorder_button.setAttribute('aria-label', 'Record or choose audio');
			recorder_button.setAttribute('data-action', 'click->editor#toggleAudioTools');
			recorder_button.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 50 50" width="15px" height="15px"><path fill="currentColor" d="M23.552 9.544C24.445 9.958 25 10.828 25 11.812v26.626c0 .959-.535 1.819-1.396 2.243-.354.174-.732.26-1.107.26-.539 0-1.073-.176-1.521-.521L11.33 33H7.5C5.57 33 4 31.43 4 29.5v-8C4 19.57 5.57 18 7.5 18h3.816l9.568-8.096C21.638 9.268 22.657 9.128 23.552 9.544zM30.857 31.474c-.071 0-.143-.015-.211-.047-.25-.116-.358-.414-.242-.664.77-1.653 1.159-3.425 1.159-5.265 0-2.186-.572-4.338-1.656-6.223-.138-.239-.055-.545.185-.683.236-.137.543-.056.683.185 1.17 2.036 1.789 4.36 1.789 6.721 0 1.987-.422 3.9-1.253 5.687C31.226 31.366 31.046 31.474 30.857 31.474zM36.643 35.268c-.086 0-.172-.021-.251-.067-.239-.139-.32-.444-.182-.684 1.54-2.653 2.354-5.687 2.354-8.771 0-3.696-1.139-7.23-3.292-10.221-.162-.224-.111-.536.113-.697.222-.164.535-.112.697.113 2.277 3.161 3.481 6.897 3.481 10.805 0 3.261-.86 6.468-2.488 9.273C36.982 35.179 36.814 35.268 36.643 35.268zM42.402 38.5c-.086 0-.172-.021-.251-.067-.238-.139-.32-.444-.182-.684 2.063-3.558 3.154-7.624 3.154-11.758 0-4.954-1.526-9.691-4.413-13.699-.162-.224-.111-.536.113-.697.221-.164.536-.112.697.113 3.011 4.179 4.603 9.118 4.603 14.283 0 4.31-1.138 8.549-3.289 12.26C42.742 38.411 42.574 38.5 42.402 38.5z"/></svg>';
			toolbar.appendChild(recorder_button);
		}

		// bold button
		bold_button = document.createElement('button');
		bold_button.onclick = makeBold;
		bold_button.id = `${textBoxID}_bold_button`;
		bold_button.className = 'editor_toolbar_button editor_bold_button editor_toolbar_margin';
		bold_button.textContent = 'b';
		bold_button.disabled = true;
		toolbar.appendChild(bold_button);

		// italic button
		const italic_button = document.createElement('button');
		italic_button.onclick = makeItalic;
		italic_button.id = `${textBoxID}_italic_button`;
		italic_button.className = 'editor_toolbar_button editor_italic_button editor_toolbar_margin';
		italic_button.textContent = 'i';
		italic_button.disabled = true;
		toolbar.appendChild(italic_button);

		// link button
		const link_button = document.createElement('button');
		link_button.onclick = makeLink;
		link_button.id = `${textBoxID}_link_button`;
		link_button.className = 'editor_toolbar_button editor_link_button';
		link_button.innerHTML = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="14px" height="14px"><path fill="currentColor" d="M 41.193359 9.8125 C 37.864609 9.8125 34.535 11.080234 32 13.615234 L 26.34375 19.271484 C 21.27375 24.341484 21.27375 32.58625 26.34375 37.65625 C 27.87875 39.19025 29.688812 40.251562 31.632812 40.851562 L 32.707031 39.777344 C 33.407031 39.077344 33.902875 38.242562 34.171875 37.351562 C 32.340875 37.076563 30.578875 36.235125 29.171875 34.828125 C 25.664875 31.321125 25.664875 25.606609 29.171875 22.099609 L 34.828125 16.443359 C 38.335125 12.936359 44.049641 12.936359 47.556641 16.443359 C 51.063641 19.950359 51.063641 25.664875 47.556641 29.171875 L 44.169922 32.558594 C 44.523922 34.397594 44.544234 36.286187 44.240234 38.117188 C 44.403234 37.968187 44.572516 37.81225 44.728516 37.65625 L 50.384766 32 C 55.454766 26.93 55.454766 18.685234 50.384766 13.615234 C 47.849766 11.080234 44.522109 9.8125 41.193359 9.8125 z M 32.369141 23.146484 L 31.294922 24.222656 C 30.594922 24.922656 30.099078 25.755484 29.830078 26.646484 C 31.661078 26.921484 33.421125 27.764875 34.828125 29.171875 C 38.335125 32.678875 38.335125 38.391438 34.828125 41.898438 L 29.171875 47.556641 C 25.664875 51.063641 19.950359 51.063641 16.443359 47.556641 C 12.936359 44.049641 12.936359 38.335125 16.443359 34.828125 L 19.830078 31.441406 C 19.476078 29.602406 19.455766 27.713812 19.759766 25.882812 C 19.596766 26.031813 19.427484 26.18775 19.271484 26.34375 L 13.615234 32 C 8.5452344 37.07 8.5452344 45.314766 13.615234 50.384766 C 18.685234 55.454766 26.93 55.454766 32 50.384766 L 37.65625 44.728516 C 42.72625 39.658516 42.72625 31.41375 37.65625 26.34375 C 36.12125 24.80975 34.312141 23.747484 32.369141 23.146484 z"/></svg>`;
		link_button.disabled = true;
		toolbar.appendChild(link_button);

		// characters remaining
		if (isShowingChars) {
			const chars_span = document.createElement("span");
			chars_span.id = `${textBoxID}_chars_span`;
			chars_span.className = 'editor_chars_remaining';
			chars_span.innerText = '';
			const chars_container = document.getElementById(`${textBoxID}_chars_container`);
			if (chars_container) {
				chars_container.appendChild(chars_span);
			}
			else {
				toolbar.appendChild(chars_span);
			}
		}

		// wrap right-aligned buttons
		const right_container = document.createElement('div')
		right_container.className = 'editor_toolbar_right';

		// progress spinner
		let img = document.createElement('img');
		img.id = `${textBoxID}_progress_spinner`;
		img.className = 'editor_progress_spinner';
		img.src = 'progress_spinner.svg';
		img.width = '25';
		img.height = '25';
		img.alt = 'Progress spinner';
		right_container.appendChild(img);

		// success checkmark
		let checkmark = document.createElement('span');
		checkmark.id = `${textBoxID}_success_checkmark`;
		checkmark.className = 'editor_success_checkmark';
		checkmark.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="25px" height="25px" baseProfile="basic"><path fill="currentColor" d="M32,10c12.131,0,22,9.869,22,22s-9.869,22-22,22s-22-9.869-22-22S19.869,10,32,10z M42.362,28.878 c0.781-0.781,0.781-2.047,0-2.828c-0.781-0.781-2.047-0.781-2.828,0l-9.121,9.121l-5.103-5.103c-0.781-0.781-2.047-0.781-2.828,0	c-0.781,0.781-0.781,2.047,0,2.828l6.517,6.517C29.374,39.789,29.883,40,30.413,40s1.039-0.211,1.414-0.586L42.362,28.878z"/></svg>';
		checkmark.width = '25';
		checkmark.height = '25';
		checkmark.alt = 'Success checkmark';
		right_container.appendChild(checkmark);

		// back or cancel button
		if (backButtonHandler) {
			const back_button = document.createElement('button');
			back_button.onclick = backButtonHandler;
			back_button.id = `${textBoxID}_back_button`;
			back_button.className = 'editor_toolbar_button editor_toolbar_margin';
			back_button.textContent = backButtonTitle;
			right_container.appendChild(back_button);
		}

		// preview button
		const preview_button = document.createElement('button');
		preview_button.onclick = togglePreview;
		preview_button.id = `${textBoxID}_preview_button`;
		preview_button.className = 'editor_toolbar_button editor_preview_button';
		preview_button.textContent = 'Preview';
		right_container.appendChild(preview_button);

		// update draft button
		if (sendDraftHandler) {
			const draft_button = document.createElement('button');
			draft_button.onclick = sendDraftHandler;
			draft_button.id = `${textBoxID}_draft_button`;
			draft_button.className = 'editor_toolbar_button editor_toolbar_margin';
			draft_button.textContent = 'Update Draft';
			right_container.appendChild(draft_button);
		}

		// post button
		if (sendPostHandler) {
			const post_button = document.createElement('button');
			post_button.onclick = sendPostHandler;
			post_button.id = `${textBoxID}_post_button`;
			post_button.className = 'editor_toolbar_button editor_post_button editor_default_button';
			post_button.textContent = sendPostTitle;
			right_container.appendChild(post_button);
		}

		toolbar.appendChild(right_container);
	}

	function setText(text, cursor_to_end = true) {
		const editor = document.getElementById(textBoxID);
		const preview = document.getElementById(textPreviewID);
		const button = document.getElementById(`${textBoxID}_preview_button`);
		isIgnoringInput = false;
		editor.innerText = text;
		editor.style.display = 'block';
		preview.style.display = 'none';
		if (button) {
			button.classList.remove('selected');
		}
		applyStyles();
		if (cursor_to_end) {
			moveCursorToEnd();
		}
		scheduleContentChanged();
	}

	function isEditorMarker(node) {
		return (node.nodeType === Node.ELEMENT_NODE) && node.matches(editorMarkerSelector);
	}

	function createEditorMarker() {
		const marker = document.createElement('span');
		marker.className = 'editor_marker';
		marker.setAttribute('data-editor-marker', 'caret');
		marker.setAttribute('aria-hidden', 'true');
		marker.textContent = '\u00a0';
		return marker;
	}

	function editorMarkerHTML() {
		return '<span class="editor_marker" data-editor-marker="caret" aria-hidden="true">&nbsp;</span>';
	}

	function editorPlainText(editor) {
		let s = '';

		function stepThroughNode(node) {
			if (isEditorMarker(node)) {
				return;
			}
			else if (node.nodeType === Node.TEXT_NODE) {
				s += node.textContent;
			}
			else if ((node.nodeType === Node.ELEMENT_NODE) && (node.nodeName == 'BR')) {
				s += '\n';
			}
			else if (node.nodeType === Node.ELEMENT_NODE) {
				for (let child = node.firstChild; child; child = child.nextSibling) {
					stepThroughNode(child);
				}
			}
		}

		stepThroughNode(editor);
		return s;
	}

	function preserveTrailingNewline(html) {
		if (html.endsWith('\n')) {
			return html + editorMarkerHTML();
		}
		else {
			return html;
		}
	}

	function formattingAncestorAtEnd(range, editor) {
		let node = range.startContainer;
		if (node.nodeType === Node.TEXT_NODE) {
			node = node.parentNode;
		}

		while (node && (node != editor)) {
			if (node.classList && containsFormattingClass(node.classList)) {
				const pos = selectionPosition(node, range.startContainer, range.startOffset);
				if (pos == logicalLength(node)) {
					return node;
				}
			}
			node = node.parentNode;
		}

		return null;
	}

	function insertLineBreakWithMarker() {
		const editor = document.getElementById(textBoxID);
		const saved_selection = saveSelection(editor);
		editor.focus();
		if (saved_selection) {
			restoreSelection(editor, saved_selection);
		}

		let selection = window.getSelection();
		if (!selection) {
			return false;
		}

		if ((selection.rangeCount == 0) || (!editor.contains(selection.getRangeAt(0).startContainer) && (selection.getRangeAt(0).startContainer != editor))) {
			editor.focus();

			const fallback_range = document.createRange();
			fallback_range.selectNodeContents(editor);
			fallback_range.collapse(false);
			selection.removeAllRanges();
			selection.addRange(fallback_range);
		}

		removeMarkerAroundCaret();

		selection = window.getSelection();
		if (!selection || (selection.rangeCount == 0)) {
			return false;
		}

		const range = selection.getRangeAt(0);
		if (!editor.contains(range.startContainer) && (range.startContainer != editor)) {
			return false;
		}

		range.deleteContents();

		const formatting_node = formattingAncestorAtEnd(range, editor);
		if (formatting_node) {
			range.setStartAfter(formatting_node);
			range.collapse(true);
		}

		const fragment = document.createDocumentFragment();
		const line_break = document.createTextNode('\n');
		const marker = createEditorMarker();
		fragment.appendChild(line_break);
		fragment.appendChild(marker);
		range.insertNode(fragment);

		range.setStart(line_break, line_break.length);
		range.setEnd(line_break, line_break.length);
		selection.removeAllRanges();
		selection.addRange(range);

		return true;
	}

	function insertLineBreakByText() {
		const editor = document.getElementById(textBoxID);
		const saved_selection = saveSelection(editor);
		const text = editorPlainText(editor);
		const position = saved_selection ? saved_selection.position : text.length;
		const next_text = text.slice(0, position) + '\n' + text.slice(position);
		const next_selection = { position: position + 1, character: '\n' };

		isIgnoringInput = true;
		editor.innerText = next_text;
		isIgnoringInput = false;

		restoreSelection(editor, next_selection);
		applyStyles();
		restoreLineBreakSelection(editor, next_text, position, next_selection);
		setTimeout(() => {
			restoreLineBreakSelection(editor, next_text, position, next_selection);
		}, 0);

		return editorPlainText(editor) == next_text;
	}

	function restoreLineBreakSelection(editor, text, position, selection) {
		if ((position + 1) == text.length) {
			moveSelectionAfterTrailingMarker(editor);
		}
		else {
			restoreSelection(editor, selection);
		}
	}

	function moveSelectionAfterTrailingMarker(editor) {
		const marker = editor.querySelector(editorMarkerSelector);
		if (!marker || !marker.parentNode) {
			return false;
		}

		const range = document.createRange();
		if (marker.firstChild && (marker.firstChild.nodeType === Node.TEXT_NODE)) {
			range.setStart(marker.firstChild, 0);
			range.setEnd(marker.firstChild, 0);
		}
		else {
			const offset = childIndex(marker);
			range.setStart(marker.parentNode, offset);
			range.setEnd(marker.parentNode, offset);
		}

		const selection = window.getSelection();
		selection.removeAllRanges();
		selection.addRange(range);
		return true;
	}

	function markerAroundCaret() {
		const editor = document.getElementById(textBoxID);
		const selection = window.getSelection();
		if (!selection || (selection.rangeCount == 0) || !selection.isCollapsed) {
			return null;
		}

		const range = selection.getRangeAt(0);
		if (!editor.contains(range.startContainer) && (range.startContainer != editor)) {
			return null;
		}

		let marker = null;
		let is_caret_inside_marker = false;
		if (range.startContainer.nodeType === Node.TEXT_NODE) {
			const parent = range.startContainer.parentNode;
			if (parent && isEditorMarker(parent)) {
				marker = parent;
				is_caret_inside_marker = true;
			}
		}
		else if ((range.startContainer.nodeType === Node.ELEMENT_NODE) && isEditorMarker(range.startContainer)) {
			marker = range.startContainer;
			is_caret_inside_marker = true;
		}
		if (range.startContainer.nodeType === Node.TEXT_NODE) {
			const node = range.startContainer.nextSibling;
			if ((range.startOffset == range.startContainer.length) && node && isEditorMarker(node)) {
				marker = node;
			}
		}
		if (!marker && (range.startContainer.nodeType === Node.ELEMENT_NODE) && (range.startOffset > 0)) {
			const node = range.startContainer.childNodes[range.startOffset - 1];
			if (node && isEditorMarker(node)) {
				marker = node;
			}
		}
		if (!marker && (range.startContainer.nodeType === Node.ELEMENT_NODE)) {
			const node = range.startContainer.childNodes[range.startOffset];
			if (node && isEditorMarker(node)) {
				marker = node;
			}
		}

		if (!marker) {
			return null;
		}

		return { marker: marker, is_caret_inside_marker: is_caret_inside_marker };
	}

	function insertTextAtMarker(text) {
		const editor = document.getElementById(textBoxID);
		const marker_info = markerAroundCaret();
		if (!marker_info) {
			return false;
		}

		const marker = marker_info.marker;
		const text_node = document.createTextNode(text);
		marker.parentNode.insertBefore(text_node, marker);
		marker.remove();
		setSelection(editor, text_node, text_node.length);
		return true;
	}

	function insertLineBreak() {
		const editor = document.getElementById(textBoxID);
		const before = editorPlainText(editor);
		const saved_selection = saveSelection(editor);
		editor.focus();
		if (saved_selection) {
			restoreSelection(editor, saved_selection);
		}
		removeMarkerAroundCaret();

		let did_insert = insertLineBreakByText();
		if (!did_insert || (editorPlainText(editor) == before)) {
			if (saved_selection) {
				restoreSelection(editor, saved_selection);
			}
			removeMarkerAroundCaret();
			did_insert = insertLineBreakWithMarker();
		}

		if (did_insert) {
			isLastCharEnter = true;
			handleEditorInput({ data: null, inputType: "insertLineBreak" });
		}

		return did_insert;
	}

	function handleEditorInput(e) {
		const is_return_input = (e.inputType == "insertParagraph") || (e.inputType == "insertLineBreak");
		const should_snapshot_for_return = isLastCharEnter || is_return_input;

		clearTimeout(undoTimer);
		undoTimer = setTimeout(() => {
			saveStateForUndo();
		}, undoDelay);

		clearTimeout(autocompleteTimer);
		autocompleteTimer = setTimeout(() => {
			checkAutocomplete();
		}, autocompleteDelay);

		// don't apply styles unless new Markdown-ish characters
		const markdown_characters = [' ', '*', '_', '[', ']', '(', ')', '<', '>', '"', '`'];
		if (e.data && markdown_characters.some(char => e.data.includes(char))) {
			applyStyles();
		}

		if (should_snapshot_for_return) {
			isLastCharEnter = false;
		}

		if ((e.data == ".") || should_snapshot_for_return) {
			checkpointUndo();
		}

		scrollIfNeeded();
		checkButtons();
		updateRemaining();
		scheduleContentChanged();
		hideSuccess();
	}

	function removeMarkerAroundCaret() {
		const selection = window.getSelection();
		const marker_info = markerAroundCaret();
		if (!marker_info) {
			return;
		}

		const range = selection.getRangeAt(0);
		const marker = marker_info.marker;
		const is_caret_inside_marker = marker_info.is_caret_inside_marker;

		if (is_caret_inside_marker) {
			const previous_node = marker.previousSibling;
			if (previous_node && (previous_node.nodeType === Node.TEXT_NODE)) {
				marker.remove();
				range.setStart(previous_node, previous_node.length);
				range.setEnd(previous_node, previous_node.length);
				selection.removeAllRanges();
				selection.addRange(range);
				return;
			}
		}

		if ((range.startContainer.nodeType === Node.TEXT_NODE) && (range.startContainer.length == 0)) {
			const caret_node = range.startContainer;
			const previous_node = caret_node.previousSibling;
			const parent = caret_node.parentNode;
			marker.remove();
			caret_node.remove();
			if (previous_node) {
				const offset = childIndex(previous_node) + 1;
				range.setStart(parent, offset);
				range.setEnd(parent, offset);
				selection.removeAllRanges();
				selection.addRange(range);
			}
			return;
		}

		const parent = marker.parentNode;
		const offset = childIndex(marker);
		marker.remove();
		range.setStart(parent, offset);
		range.setEnd(parent, offset);
		selection.removeAllRanges();
		selection.addRange(range);
	}

	function getMarkdownByID(div_id) {
		let s = editorPlainText(document.getElementById(div_id));

		// sometimes we get an extra return after code blocks
		s = s.replace(/```\n\n/g, '```\n');

		return s;
	}

	function getMarkdown() {
		return getMarkdownByID(textBoxID);
	}

	function getHTML() {
		return markdownToHTML(getMarkdown());
	}

	function contentMetrics() {
		let markdown = getMarkdown();
		let html = markdownToHTML(markdown);
		html = html.replace("</p>\n<p>", "</p>\n\n<p>"); // better account for what Markdown looked like
		let text_only = html.replace(/<\/?[^>]+(>|$)/g, "");
		const is_blockquote = html.includes("<blockquote");
		const is_photo = html.includes("<img");

		let len;
		if ((typeof Intl !== 'undefined') && ('Segmenter' in Intl)) {
			len = Array.from(new Intl.Segmenter().segment(text_only)).length;
		}
		else {
			len = Array.from(text_only).length;
		}

		const max_length = is_blockquote ? maxBlockquoteLength : maxCharsLength;
		return {
			markdown: markdown,
			count: len,
			max: max_length,
			remaining: max_length - len,
			is_blockquote: is_blockquote,
			is_photo: is_photo
		};
	}

	function markdownToHTML(markdown) {
		let s = applyMicroMarkup(markdown);
		const converter = new showdown.Converter();
		return converter.makeHtml(s);
	}

	function scheduleContentChanged() {
		if (!contentChangeHandler) {
			return;
		}

		clearTimeout(contentChangeTimer);
		contentChangeTimer = setTimeout(() => {
			contentChangeTimer = null;
			try {
				contentChangeHandler(contentMetrics());
			}
			catch (error) {
				console.error("Content metrics error", error);
			}
		}, contentChangeDelay);
	}

	function cancelListeners() {
		// cancel timers
		clearTimeout(undoTimer);
		clearTimeout(autocompleteTimer);
		clearTimeout(contentChangeTimer);

		// replace with clone which clears listeners
		const editor = document.getElementById(textBoxID);
		const new_element = editor.cloneNode(true);
		editor.parentNode.replaceChild(new_element, editor);
	}

	function setupListeners() {
		if (hasFinishedSetup) {
			return;
		}

		hasFinishedSetup = true;

		document.getElementById(textBoxID).addEventListener('input', function (e) {
			handleEditorInput(e);
		});

		document.getElementById(textBoxID).addEventListener('beforeinput', function (e) {
			if (e.isComposing) {
				return;
			}

			if ((e.inputType == "insertParagraph") || (e.inputType == "insertLineBreak")) {
				e.preventDefault();
				insertLineBreak();
			}
			else if ((e.inputType == "insertText") && e.data && markerAroundCaret()) {
				e.preventDefault();
				if (insertTextAtMarker(e.data)) {
					handleEditorInput(e);
				}
			}
		});

		document.getElementById(textBoxID).addEventListener('compositionstart', function (e) {
			// for languages like Japanese or Chinese, we disable Markdown coloring
			isIgnoringInput = true;
		});

		document.getElementById(textBoxID).addEventListener('keydown', function (e) {
			const is_apple = /Mac|iPod|iPhone|iPad/.test(navigator.platform);
			const is_modifier = is_apple ? e.metaKey : e.ctrlKey;
			const arrow_keys = ['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown'];
			if (e.key == "Backspace") {
				removeMarkerAroundCaret();
			}

			if (arrow_keys.includes(e.key)) {
				checkpointUndo();
			}

			if (is_modifier && (e.key == "b")) {
				e.preventDefault();
				makeBold();
				return;
			}
			else if (is_modifier && (e.key == "i")) {
				e.preventDefault();
				makeItalic();
				return;
			}
			else if (is_modifier && (e.key == "k")) {
				e.preventDefault();
				makeLink();
				return;
			}
			else if (is_modifier && e.shiftKey && (e.key == "z")) {
				e.preventDefault();
				redo();
				return;
			}
			else if (is_modifier && (e.key == "z")) {
				e.preventDefault();
				undo();
				return;
			}
			else if (is_modifier && (e.key == "a")) {
				isSelectAll = true;
				return;
			}
			else if (is_modifier && (e.key == "s")) {
				if (saveHandler) {
					saveHandler(e);
				}
				else if (sendDraftHandler) {
					sendDraftHandler(e);
				}
				else if (sendPostHandler) {
					sendPostHandler(e);
				}
				return;
			}
			else if (is_modifier && (e.key == "Enter")) {
				e.preventDefault();
				if (sendPostHandler) {
					let post_button = document.getElementById(`${textBoxID}_post_button`);
					post_button.click();
				}
				return;
			}
			else if (e.key == "Enter") {
				// languages like Japanese or Chinese
				if (e.isComposing) {
					return;
				}

				e.preventDefault();
				insertLineBreak();
				return;
			}
			else if (/^[a-z]$/i.test(e.key)) {
				// for a-z, we don't apply styles to avoid spelling underline flicker
				isIgnoringInput = true;
			}
			else {
				isSelectAll = false;
			}
		});

		document.getElementById(textBoxID).addEventListener('keyup', function (e) {
			// languages like Japanese or Chinese
			if (e.isComposing) {
				return;
			}

			// don't do anything special for some keys
			const keys = ['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown', 'Meta', 'Control', 'Enter'];
			if (keys.includes(e.key)) {
				return;
			}

			// ignore select-all too
			if (isSelectAll) {
				return;
			}

			// ready to apply styles again
			isIgnoringInput = false;
		});

		document.addEventListener('selectionchange', function (e) {
			const editor = document.getElementById(textBoxID);
			const bold_button = document.getElementById(`${textBoxID}_bold_button`);
			const italic_button = document.getElementById(`${textBoxID}_italic_button`);
			const link_button = document.getElementById(`${textBoxID}_link_button`);
			const selection = document.getSelection();

			// check if selection is in the editor div and not empty
			if (selection.rangeCount > 0) {
				const range = selection.getRangeAt(0);
				// check if the start or end is within editor
				if (editor.contains(range.startContainer) && editor.contains(range.endContainer) && !selection.isCollapsed) {
					bold_button.disabled = false;
					italic_button.disabled = false;
					link_button.disabled = false;
				}
				else {
					// wait to disable buttons until some action
					// to avoid confusion when buttons change right away
					isNextButtonDisable = true;
				}
			}
		});

		document.getElementById(textBoxID).addEventListener('paste', function (e) {
			e.preventDefault();
			removeMarkerAroundCaret();

			// get just the text from the clipboard
			const clipboard_data = e.clipboardData || window.clipboardData;
			const text = clipboard_data.getData('text');
			if (text.length > 0) {
				isIgnoringInput = false;

				let s = replaceDuplicateReturns(text);
				document.execCommand('insertText', false, s);
			}
			else {
				// try to get pasted images
				const items = clipboard_data.items;
				for (let i = 0; i < items.length; i++) {
					if (items[i].type.indexOf('image') != -1) {
						const blob = items[i].getAsFile();
						const reader = new FileReader();

						reader.onload = function (e) {
							// show spinner while we upload the file
							showProgress();

							// get ArrayBuffer and make a blob from it
							const buffer = e.target.result;
							const new_blob = new Blob([buffer], { type: blob.type });

							// send via Micropub, then insert tag
							uploadFileData(new_blob, blob.type, function (new_url) {
								let img_tag = `<img src="${new_url}" alt="">`;
								isIgnoringInput = false;
								document.execCommand('insertText', false, img_tag);
								hideProgress();
							});
						};

						reader.readAsDataURL(blob);
					}
				}
			}
		});

		document.getElementById(textBoxID).addEventListener('dragover', function (e) {
			e.preventDefault();
			e.stopPropagation();
			document.getElementById(textBoxID).classList.add('editor_drag_active');
		});

		document.getElementById(textBoxID).addEventListener('dragleave', function (e) {
			e.preventDefault();
			e.stopPropagation();
			document.getElementById(textBoxID).classList.remove('editor_drag_active');
		});

		document.getElementById(textBoxID).addEventListener('drop', function (e) {
			e.preventDefault();
			e.stopPropagation();
			document.getElementById(textBoxID).classList.remove('editor_drag_active');

			if (dropHandler) {
				const files = e.dataTransfer.files;
				if (files.length > 0) {
					dropHandler(files);
				}
			}
		});
	}

	function setupFocus() {
		const editor = document.getElementById(textBoxID);
		editor.focus();
		applyStyles();
		saveStateForUndo();
	}

	function saveStateForUndo() {
		// add latest text state
		let editor = document.getElementById(textBoxID);
		let s = editorPlainText(editor);
		let selection = saveSelection(editor);
		let last_state = undoStack[undoStack.length - 1];
		if (last_state && last_state.text == s) {
			return;
		}
		undoStack.push({ text: s, selection: selection });
		redoStack = [];

		// only keep recent changes
		if (undoStack.length > undoMaxSize) {
			undoStack.shift();  // remove oldest
		}
	}

	function checkpointUndo() {
		clearTimeout(undoTimer);
		saveStateForUndo();
	}

	function checkLength(text = "") {
		let s = text;
		if (s.length == 0) {
			// if no text, get current text
			const editor = document.getElementById(textBoxID);
			s = editorPlainText(editor);
		}

		// for longer text, we disable the highlighting
		const max_length_for_highlighting = 5000;
		return (s.length > max_length_for_highlighting);
	}

	function showSuccess() {
		const checkmark = document.getElementById(`${textBoxID}_success_checkmark`);
		if (!checkmark) {
			return;
		}

		if (successTimer) {
			clearTimeout(successTimer);
			successTimer = null;
		}
		if (successFadeTimer) {
			clearTimeout(successFadeTimer);
			successFadeTimer = null;
		}

		checkmark.removeEventListener("transitionend", finishSuccessFade);

		isSuccessVisible = true;
		isSuccessFading = false;

		checkmark.style.display = "inline-block";
		checkmark.style.opacity = "1";
		checkmark.style.transition = "opacity 0.6s ease";

		successTimer = setTimeout(() => {
			successTimer = null;
			fadeSuccess();
		}, 5000);
	}

	function hideSuccess() {
		if (successTimer) {
			return;
		}
		fadeSuccess();
	}

	function fadeSuccess() {
		if (!isSuccessVisible || isSuccessFading) {
			return;
		}

		const checkmark = document.getElementById(`${textBoxID}_success_checkmark`);
		if (!checkmark) {
			return;
		}

		isSuccessFading = true;
		checkmark.style.opacity = "0";
		checkmark.addEventListener("transitionend", finishSuccessFade);

		successFadeTimer = setTimeout(() => {
			finishSuccessFade();
		}, 800);
	}

	function finishSuccessFade(e) {
		const checkmark = document.getElementById(`${textBoxID}_success_checkmark`);
		if (!checkmark) {
			return;
		}

		if (e && e.target !== checkmark) {
			return;
		}

		checkmark.removeEventListener("transitionend", finishSuccessFade);
		checkmark.style.display = "none";
		checkmark.style.opacity = "";
		checkmark.style.transition = "";

		isSuccessVisible = false;
		isSuccessFading = false;

		if (successFadeTimer) {
			clearTimeout(successFadeTimer);
			successFadeTimer = null;
		}
	}

	function showProgress(options = {}) {
		const disablePostButton = options.disablePostButton !== false;

		// show spinner
		const progress_spinner = document.getElementById(`${textBoxID}_progress_spinner`);
		progress_spinner.style.display = "inline-block";

		// also disable post button
		if (disablePostButton) {
			const post_button = document.getElementById(`${textBoxID}_post_button`);
			if (post_button) {
				post_button.disabled = true;
			}
		}
	}

	function hideProgress(options = {}) {
		const disablePostButton = options.disablePostButton !== false;

		// hide spinner
		const progress_spinner = document.getElementById(`${textBoxID}_progress_spinner`);
		progress_spinner.style.display = "none";

		// also enable post button
		if (disablePostButton) {
			const post_button = document.getElementById(`${textBoxID}_post_button`);
			if (post_button) {
				post_button.disabled = false;
			}
		}
	}

	function hideCharsRemaining() {
		setCharsRemainingVisibility(false);
	}

	function setCharsRemainingVisibility(is_visible) {
		const chars_span = document.getElementById(`${textBoxID}_chars_span`);
		if (!chars_span) {
			return;
		}

		const container = chars_span.parentElement;
		if (container && container.classList.contains("editor_chars_container")) {
			container.style.display = is_visible ? "" : "none";
		}
		else {
			chars_span.style.display = is_visible ? "" : "none";
		}
	}

	function mimeToExtension(mimeType) {
		const extensions = {
			'image/jpeg': 'jpg',
			'image/png': 'png',
			'image/gif': 'gif',
			'image/webp': 'webp',
			'image/svg+xml': 'svg',
			'image/heic': 'heic'
		};

		return extensions[mimeType] || 'bin';
	}

	function uploadFileData(blob, type, completionHandler) {
		let new_url = "";

		const form = new FormData();
		const ext = mimeToExtension(type);
		const filename = `image.${ext}`;
		form.append('file', blob, filename);

		fetch("/micropub/media", {
			method: "POST",
			body: form
		})
			.then(response => response.json()).then(data => {
				new_url = data.url;
				console.log("Upload success", new_url, data);
				completionHandler(new_url);
			})
			.catch((error) => {
				console.error("Upload error", error);
				completionHandler(new_url);
			});
	}

	function replaceUsername(partial_username, full_username) {
		const editor = document.getElementById(textBoxID);
		let s = editorPlainText(editor);

		const partial_regex = new RegExp(partial_username + '$');
		s = s.replace(partial_regex, full_username);

		editor.innerText = s;
		applyStyles();
		scheduleContentChanged();
		setTimeout(() => {
			moveCursorToEnd();
		}, 200);
	}

	function togglePreview(html) {
		html = html || "";

		let editor = document.getElementById(textBoxID);
		let preview = document.getElementById(textPreviewID);
		let button = document.getElementById(`${textBoxID}_preview_button`);
		button.classList.toggle('selected');

		if (editor.style.display != 'none') {
			preview.innerHTML = html;
			editor.style.display = 'none';
			preview.style.display = 'block';
			setPreviewBackground(true);
			setCharsRemainingVisibility(false);
		}
		else {
			editor.style.display = 'block';
			preview.style.display = 'none';
			setPreviewBackground(false);
			updateRemaining();
			scheduleContentChanged();
			editor.focus();
		}
	}

	function setPreviewBackground(is_previewing) {
		document.body.classList.toggle('inkwell_previewing', !!is_previewing);
	}

	function applyMicroMarkup(text) {
		let s = text;

		// Micro.blog also auto-links usernames
		const username_regex = /@([a-zA-Z0-9@]+(?:\.[a-zA-Z]+)*)/g;
		s = s.replace(username_regex, '<a href="https://micro.blog/$1">@$1</a>');

		// ...and plain URLs
		// ...

		return s;
	}

	function makeBold(e = null) {
		if (e) {
			e.preventDefault();
		}
		makeMarkup("**");
	}

	function makeItalic(e = null) {
		if (e) {
			e.preventDefault();
		}
		makeMarkup("_");
	}

	function makeLink(e = null) {
		if (e) {
			e.preventDefault();
		}
		makeMarkup("[", "]()");
	}

	function makeMarkup(surroundingText, extraText = "") {
		let selection = window.getSelection();
		let range = selection.getRangeAt(0);
		let selected_text = selection.toString();

		if (!selected_text) {
			return;
		}

		// create a new text node with markup
		let s;
		if (extraText.length > 0) {
			s = `${surroundingText}${selected_text}${extraText}`;
		}
		else {
			s = `${surroundingText}${selected_text}${surroundingText}`;
		}
		let markup_text = document.createTextNode(s);

		// replace the selected text with the new text
		range.deleteContents();
		range.insertNode(markup_text);

		// clear the current selection and set it to just after the inserted text
		selection.removeAllRanges();
		let new_range = document.createRange();

		// if link, set the cursor to 1 character previous (in between parenthesis)
		if (extraText.length > 0) {
			new_range.setStart(markup_text, markup_text.length - 1);
			new_range.setEnd(markup_text, markup_text.length - 1);
		}
		else {
			new_range.setStart(markup_text, markup_text.length);
			new_range.setEnd(markup_text, markup_text.length);
		}

		selection.addRange(new_range);

		applyStyles();
		scheduleContentChanged();
	}

	function undo() {
		if (undoStack.length > 0) {
			const editor = document.getElementById(textBoxID);
			const current_state = {
				text: editorPlainText(editor),
				selection: saveSelection(editor)
			};
			const last_state = undoStack[undoStack.length - 1];
			if (last_state && last_state.text == current_state.text) {
				if (undoStack.length == 1) {
					return;
				}
				redoStack.push(last_state);
				undoStack.pop();
			}
			else {
				redoStack.push(current_state);
			}

			let prev_state = undoStack[undoStack.length - 1];
			if (!prev_state) {
				prev_state = { text: "", selection: null };
			}
			editor.innerText = prev_state.text;
			applyStyles();
			scheduleContentChanged();
			if (prev_state.selection) {
				restoreSelection(editor, prev_state.selection);
			}
		}
	}

	function redo() {
		if (redoStack.length > 0) {
			const editor = document.getElementById(textBoxID);
			const current_state = {
				text: editorPlainText(editor),
				selection: saveSelection(editor)
			};
			const last_state = undoStack[undoStack.length - 1];
			if (!last_state || (last_state.text != current_state.text)) {
				undoStack.push(current_state);
			}

			const next_state = redoStack.pop();
			editor.innerText = next_state.text;
			applyStyles();
			scheduleContentChanged();
			if (next_state.selection) {
				restoreSelection(editor, next_state.selection);
			}
		}
	}

	function moveCursorToEnd() {
		const editor = document.getElementById(textBoxID);

		debugLog("move to end");

		// create a range at end of the content
		const range = document.createRange();
		range.selectNodeContents(editor);
		range.collapse(false);

		// remove existing selection
		const selection = window.getSelection();
		selection.removeAllRanges();

		// add the new range (cursor) to the selection
		selection.addRange(range);
	}

	function childIndex(node) {
		let index = 0;
		while (node && node.previousSibling) {
			index++;
			node = node.previousSibling;
		}
		return index;
	}

	function logicalLength(node) {
		if (isEditorMarker(node)) {
			return 0;
		}
		else if (node.nodeType === Node.TEXT_NODE) {
			return node.textContent.length;
		}
		else if ((node.nodeType === Node.ELEMENT_NODE) && (node.nodeName == 'BR')) {
			return 1;
		}
		else if (node.nodeType === Node.ELEMENT_NODE) {
			let len = 0;
			for (let child = node.firstChild; child; child = child.nextSibling) {
				len += logicalLength(child);
			}
			return len;
		}
		else {
			return 0;
		}
	}

	function selectionPosition(containerElement, targetNode, targetOffset) {
		let current_pos = 0;
		let found = false;

		function stepThroughNode(node) {
			if (found || isEditorMarker(node)) {
				return;
			}

			if (node == targetNode) {
				if (node.nodeType === Node.TEXT_NODE) {
					current_pos += Math.min(targetOffset, node.textContent.length);
				}
				else if (node.nodeType === Node.ELEMENT_NODE) {
					const child_count = Math.min(targetOffset, node.childNodes.length);
					for (let i = 0; i < child_count; i++) {
						current_pos += logicalLength(node.childNodes[i]);
					}
				}
				found = true;
				return;
			}

			if (node.nodeType === Node.TEXT_NODE) {
				current_pos += node.textContent.length;
			}
			else if ((node.nodeType === Node.ELEMENT_NODE) && (node.nodeName == 'BR')) {
				current_pos++;
			}
			else if (node.nodeType === Node.ELEMENT_NODE) {
				for (let child = node.firstChild; child; child = child.nextSibling) {
					stepThroughNode(child);
				}
			}
		}

		stepThroughNode(containerElement);

		return current_pos;
	}

	function setSelection(containerElement, node, offset) {
		const range = document.createRange();
		range.setStart(node, offset);
		range.setEnd(node, offset);

		const sel = window.getSelection();
		sel.removeAllRanges();
		sel.addRange(range);
	}

	function saveSelection(containerElement) {
		const selection = window.getSelection();

		if (selection.rangeCount == 0) {
			debugLog("no selection found");
			return null;
		}

		const range = selection.getRangeAt(0);
		if (!containerElement.contains(range.startContainer) && (range.startContainer != containerElement)) {
			return null;
		}

		const position = selectionPosition(containerElement, range.startContainer, range.startOffset);
		const text = editorPlainText(containerElement);
		const character = position > 0 ? text[position - 1] : '';

		debugLog("saving selection", position);

		return { position: position, character: character };
	}

	function restoreSelection(containerElement, saved) {
		if (!saved) {
			return;
		}

		const target_pos = Math.max(0, saved.position);
		let current_pos = 0;
		let did_restore = false;

		debugLog("restore selection", target_pos);

		function restoreAtElementOffset(node, offset) {
			try {
				setSelection(containerElement, node, offset);
				did_restore = true;
			}
			catch (error) {
				debugLog("error", error);
			}
		}

		function stepThroughNode(node) {
			if (did_restore || isEditorMarker(node)) {
				return;
			}

			if (node.nodeType === Node.TEXT_NODE) {
				const len = node.textContent.length;
				if (target_pos <= (current_pos + len)) {
					restoreAtElementOffset(node, target_pos - current_pos);
				}
				else {
					current_pos += len;
				}
			}
			else if ((node.nodeType === Node.ELEMENT_NODE) && (node.nodeName == 'BR')) {
				const next_pos = current_pos + 1;
				if (target_pos <= next_pos) {
					restoreAtElementOffset(node.parentNode, childIndex(node) + 1);
				}
				else {
					current_pos = next_pos;
				}
			}
			else if (node.nodeType === Node.ELEMENT_NODE) {
				for (let child = node.firstChild; child; child = child.nextSibling) {
					stepThroughNode(child);
				}
			}
		}

		if (target_pos == 0) {
			restoreAtElementOffset(containerElement, 0);
			return;
		}

		stepThroughNode(containerElement);

		if (!did_restore) {
			restoreAtElementOffset(containerElement, containerElement.childNodes.length);
		}
	}

	function containsFormattingClass(parentClassList) {
		return parentClassList.contains('editor_bold') ||
			parentClassList.contains('editor_italic') ||
			parentClassList.contains('editor_link_text') ||
			parentClassList.contains('editor_link_url') ||
			parentClassList.contains('editor_quote') ||
			parentClassList.contains('editor_attr_name') ||
			parentClassList.contains('editor_attr_value');
	}

	function replaceDuplicateReturns(text) {
		let s = text
		s = s.replace(/\r?\n/g, '\r\n');
		s = s.replace(/\n{3,}/g, '\n\n');
		return s;
	}

	function applyStyles() {
		if (isIgnoringInput) return;
		if (checkLength()) return;

		const editor = document.getElementById(textBoxID);
		let saved = saveSelection(editor);
		if (!saved || (saved.character == '')) {
			debugLog("no saved");
		}

		const bold_regex = /\*\*(.*?)\*\*/g;
		//		const italic_regex = /(?<!<[^<>]*)_(?!<)([^_]+)(?!>)(?<!>)_(?!>[^<>]*>)/g;
		const italic_regex = /(?<!<[^<>]*)_(?!<)(?![^()]*\))([^_()]+)(?![^()]*\()(?<!>)_(?!>[^<>]*>)/g;
		const link_regex = /\[([^\]\r\n]+)\]\(([^\)\r\n]*)\)/g;
		const quote_regex = /^>(.*)/gm;
		const tag_open_regex = /<([a-zA-Z\/]*)/g;

		const tag_close_regex = /([_>\"a-zA-Z]*)(>)/g;

		const attr_regex = /([a-zA-Z]+)="([^"<>]*)"/g;
		const code_block_regex = /(```.+```)/gs;
		const code_inline_regex = /(?<!`)`([^`]+)`(?!`)/g;
		const header_regex = /^(#+ .*)$/gm;
		const divider_regex = /(-{3,})/g;
		const username_regex = /@([a-zA-Z0-9@]+(?:\.[a-zA-Z]+)*)/g;
		const url_regex = /\bhttps?:\/\/[^\s<()]+(?:\([^\s<()]*\)[^\s<()]*)*/g;

		// start with the plain content
		let plain_text = editorPlainText(editor);
		let s = plain_text;
		const urls = [];
		s = s.replace(url_regex, (match) => {
			const index = urls.length;
			urls.push(match);
			return `⟦URL${index}⟧`;
		});

		debugLog("got text:", s);

		// apply HTML tag formatting first because we'll be adding other span tags
		s = s.replace(tag_open_regex, '<span class="editor_tag">&lt;$1</span>');

		s = s.replace(tag_close_regex, (match, tag, greater_than) => {
			if ((tag == "") || (tag == "span") || (tag.includes("editor_"))) {
				// don't try to replace our own special classes
				return match;
			}
			else {
				return `${tag}<span class="editor_tag">&gt;</span>`;
			}
		});

		s = s.replace(attr_regex, (match, key, value, offset, original) => {
			if ((key == "class") && (value.includes("editor_"))) {
				// don't try to replace our own special classes
				return match;
			}
			else {
				return `<span class="editor_attr_name">${key}</span>=<span class="editor_attr_value">"${value}"</span>`;
			}
		});

		// apply Markdown styles
		s = s.replace(bold_regex, '<span class="editor_bold">**$1**</span>');
		s = s.replace(italic_regex, '<span class="editor_italic">_$1_</span>');
		s = s.replace(link_regex, '<span class="editor_link_text">[$1]</span><span class="editor_link_url">($2)</span>');
		s = s.replace(quote_regex, '<span class="editor_quote">&gt;$1</span>');
		s = s.replace(code_block_regex, '<span class="editor_code_block">$1</span>');
		s = s.replace(code_inline_regex, '<span class="editor_code_inline">`$1`</span>');
		s = s.replace(header_regex, '<span class="editor_header">$1</span>');
		s = s.replace(divider_regex, '<span class="editor_divider">$1</span>');
		s = s.replace(username_regex, '<span class="editor_username">@$1</span>');
		s = s.replace(/⟦URL(\d+)⟧/g, (match, index) => {
			return urls[Number(index)] || match;
		});

		debugLog("replacing with:", s);

		s = preserveTrailingNewline(s);

		// set the new HTML and restore cursor
		isIgnoringInput = true;
		editor.innerHTML = s;
		if (saved) {
			restoreSelection(editor, saved);
		}
		isIgnoringInput = false;
	}

	function scrollIfNeeded() {
		requestAnimationFrame(() => {
			const range = document.createRange();
			const selection = window.getSelection();
			if (selection.rangeCount > 0) {
				const editor = document.getElementById(textBoxID);

				const range = selection.getRangeAt(0);
				const selection_rect = range.getBoundingClientRect();
				const div_rect = editor.getBoundingClientRect();

				// if the cursor is below the visible area of the div
				if (selection_rect.bottom > div_rect.bottom) {
					editor.scrollTop += (selection_rect.bottom - div_rect.bottom);
				}
			}
		});
	}

	function checkButtons() {
		if (isNextButtonDisable) {
			const bold_button = document.getElementById(`${textBoxID}_bold_button`);
			const italic_button = document.getElementById(`${textBoxID}_italic_button`);
			const link_button = document.getElementById(`${textBoxID}_link_button`);

			bold_button.disabled = true;
			italic_button.disabled = true;
			link_button.disabled = true;

			isNextButtonDisable = false;
		}
	}

	function checkAutocomplete() {
		if (!autocompleteHandler) {
			return;
		}

		const s = editorPlainText(document.getElementById(textBoxID));

		const last_username_regex = /@([a-zA-Z0-9@]+(?:\.[a-zA-Z]+)*)$/g;
		const match = s.match(last_username_regex);
		let last_username = match ? match[0] : "";

		autocompleteHandler(last_username);
	}

	function expandBox() {
		// show title field and update box height
		document.getElementById("posting_title_container").style.display = "block";
		document.getElementById(textBoxID).style.transition = "height 0.3s ease-in-out";
		document.getElementById(textBoxID).style.height = "calc(100vh - 250px)";
		document.getElementById(textPreviewID).style.height = "calc(100vh - 270px)";

		// don't animate anymore after expanded
		setTimeout(() => {
			document.getElementById(textBoxID).classList.add("no_transition");
		}, 1000);
		
		// dispatch event so controller can extract title from content
		document.dispatchEvent(new CustomEvent("editor:titleBarShown"));
	}

	function updateRemaining() {
		const chars_span = document.getElementById(`${textBoxID}_chars_span`);
		if (!chars_span) {
			return;
		}

		// if there's a title, hide the character count
		const title_field = document.getElementById("input_title");
		if (title_field && (title_field.value.trim() != "")) {
			chars_span.classList.remove("editor_chars_error");
			const container = chars_span.parentElement;
			if (container && container.classList.contains("editor_chars_container")) {
				container.style.display = "none";
			}
			else {
				chars_span.style.display = "none";
			}
			return;
		}
		const container = chars_span.parentElement;
		if (container && container.classList.contains("editor_chars_container")) {
			container.style.display = "";
		}
		chars_span.style.display = "";

		const metrics = contentMetrics();
		const len = metrics.count;
		const is_blockquote = metrics.is_blockquote;
		const is_photo = metrics.is_photo;

		if (len == 0) {
			chars_span.innerText = "";
		}
		else if (is_blockquote) {
			chars_span.innerText = `${len}/${maxBlockquoteLength}`;
		}
		else {
			chars_span.innerText = `${len}/${maxCharsLength}`;
		}

		if (len > maxCharsLength) {
			if (is_blockquote && (len <= maxBlockquoteLength)) {
				chars_span.classList.remove("editor_chars_error");
			}
			else {
				chars_span.classList.add("editor_chars_error");
				expandBox();
			}
		}
		else {
			chars_span.classList.remove("editor_chars_error");
		}

		if (is_photo) {
			expandBox();
		}
	}

	return { init: init, getMarkdownByID: getMarkdownByID };
})();
