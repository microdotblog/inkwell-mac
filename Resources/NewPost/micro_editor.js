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
		const selection = window.getSelection();
		if (selection && (selection.rangeCount > 0) && !selection.isCollapsed) {
			const range = selection.getRangeAt(0);
			if (editor.contains(range.startContainer) && editor.contains(range.endContainer)) {
				checkpointUndo();
				range.deleteContents();
			}
		}

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
		return editorPlainText(document.getElementById(div_id));
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

		document.getElementById(textBoxID).addEventListener('copy', function (e) {
			const editor = document.getElementById(textBoxID);
			const selection = window.getSelection();
			if (!e.clipboardData || !selection || (selection.rangeCount == 0) || selection.isCollapsed) {
				return;
			}

			const parts = [];
			for (let i = 0; i < selection.rangeCount; i++) {
				const selected_range = selection.getRangeAt(i);
				if (!editor.contains(selected_range.startContainer) || !editor.contains(selected_range.endContainer)) {
					return;
				}

				// Keep partially selected caret markers wrapped so text extraction can omit them.
				const range = selected_range.cloneRange();
				const start_node = selected_range.startContainer;
				const end_node = selected_range.endContainer;
				const start_element = start_node.nodeType == Node.ELEMENT_NODE ? start_node : start_node.parentElement;
				const end_element = end_node.nodeType == Node.ELEMENT_NODE ? end_node : end_node.parentElement;
				const start_marker = start_element?.closest(editorMarkerSelector);
				const end_marker = end_element?.closest(editorMarkerSelector);
				if (start_marker) {
					range.setStartBefore(start_marker);
				}
				if (end_marker) {
					range.setEndAfter(end_marker);
				}
				const container = document.createElement('div');
				container.appendChild(range.cloneContents());
				parts.push(editorPlainText(container));
			}

			e.clipboardData.setData('text/plain', parts.join(''));
			e.preventDefault();
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
		const username_regex = /@([a-zA-Z0-9_@-]+(?:\.[a-zA-Z0-9_@-]+)*)/g;
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

	function escapeEditorHTML(text) {
		return String(text)
			.replace(/&/g, '&amp;')
			.replace(/</g, '&lt;')
			.replace(/>/g, '&gt;')
			.replace(/"/g, '&quot;')
			.replace(/'/g, '&#39;');
	}

	function formatHTMLTag(text) {
		if (text.startsWith('<!') || text.startsWith('<?')) {
			return `<span class="editor_tag">${escapeEditorHTML(text)}</span>`;
		}

		let current_pos = text[1] == '/' ? 2 : 1;
		while (/[A-Za-z0-9:-]/.test(text[current_pos] ?? '')) {
			current_pos++;
		}
		let formatted = escapeEditorHTML(text.substring(0, current_pos));

		while (current_pos < text.length) {
			const char = text[current_pos];
			if (isWhitespace(char) || (char == '/') || (char == '>')) {
				formatted += escapeEditorHTML(char);
				current_pos++;
				continue;
			}

			const name_start = current_pos;
			while ((current_pos < text.length) && !/[\s=/>]/.test(text[current_pos])) {
				current_pos++;
			}
			formatted += `<span class="editor_attr_name">${escapeEditorHTML(text.substring(name_start, current_pos))}</span>`;
			while (isWhitespace(text[current_pos])) {
				formatted += escapeEditorHTML(text[current_pos]);
				current_pos++;
			}
			if (text[current_pos] != '=') {
				continue;
			}

			formatted += '=';
			current_pos++;
			while (isWhitespace(text[current_pos])) {
				formatted += escapeEditorHTML(text[current_pos]);
				current_pos++;
			}
			const value_start = current_pos;
			const quote = ((text[current_pos] == '"') || (text[current_pos] == "'")) ? text[current_pos] : null;
			if (quote) {
				current_pos++;
				while ((current_pos < text.length) && (text[current_pos] != quote)) {
					current_pos++;
				}
				if (text[current_pos] == quote) {
					current_pos++;
				}
			}
			else {
				while ((current_pos < text.length) && !/[\s>]/.test(text[current_pos])) {
					current_pos++;
				}
			}
			formatted += `<span class="editor_attr_value">${escapeEditorHTML(text.substring(value_start, current_pos))}</span>`;
		}

		return `<span class="editor_tag">${formatted}</span>`;
	}

	function createPlaceholderStore(text) {
		let attempt = 0;
		let prefix = `\uE000${text.length}\uE001`;
		while (text.includes(prefix)) {
			attempt++;
			prefix = `\uE000${text.length}:${attempt}\uE001`;
		}

		const entries = [];
		const token_source = `${prefix}(\\d+)${prefix}`;

		function add(type, value) {
			const index = entries.length;
			entries.push({ type: type, value: value });
			return `${prefix}${index}${prefix}`;
		}

		function tokenAt(value, position, type) {
			if (!value.startsWith(prefix, position)) {
				return null;
			}
			const index_start = position + prefix.length;
			const token_end = value.indexOf(prefix, index_start);
			if (token_end == -1) {
				return null;
			}
			const index_text = value.substring(index_start, token_end);
			if (!/^\d+$/.test(index_text)) {
				return null;
			}
			const entry = entries[Number(index_text)];
			if (!entry || (entry.type != type)) {
				return null;
			}
			return { end: token_end + prefix.length };
		}

		function rawText(value) {
			// outer atoms can contain tokens created by earlier protection passes
			const token_regex = new RegExp(token_source, 'g');
			return value.replace(token_regex, (match, index) => {
				const nested_entry = entries[Number(index)];
				if (!nested_entry || (nested_entry.type == 'markup')) {
					return match;
				}
				return rawText(nested_entry.value);
			});
		}

		function restore(value) {
			const token_regex = new RegExp(token_source, 'g');
			return value.replace(token_regex, (match, index) => {
				const entry = entries[Number(index)];
				if (!entry) {
					return match;
				}
				if (entry.type == 'markup') {
					return entry.value;
				}

				const raw_value = rawText(entry.value);
				if (entry.type == 'html_tag') {
					return formatHTMLTag(raw_value);
				}

				const escaped_value = escapeEditorHTML(raw_value);
				if (entry.type == 'code_block') {
					return `<span class="editor_code_block">${escaped_value}</span>`;
				}
				else if (entry.type == 'code_inline') {
					return `<span class="editor_code_inline">${escaped_value}</span>`;
				}
				return escaped_value;
			});
		}

		return { add: add, tokenAt: tokenAt, restore: restore };
	}

	function isEscaped(text, position) {
		let slash_count = 0;
		for (let i = position - 1; (i >= 0) && (text[i] == '\\'); i--) {
			slash_count++;
		}
		return ((slash_count % 2) == 1);
	}

	function isSpaceOrTab(char) {
		return (char == ' ') || (char == '\t');
	}

	function isWhitespace(char) {
		return !char || /\s/u.test(char);
	}

	function lineEnd(text, start) {
		let end = text.indexOf('\n', start);
		if (end == -1) {
			end = text.length;
		}
		if ((end > start) && (text[end - 1] == '\r')) {
			end--;
		}
		return end;
	}

	function findMarkdownTargetEnd(text, start, limit, closing_char, allow_empty, recovery_starts = null) {
		let current_pos = start;
		let destination_end = start;

		// angle-wrapped destinations have their own delimiter rules
		if (text[current_pos] == '<') {
			current_pos++;
			let found_angle_end = false;
			let escaped = false;
			while (current_pos < limit) {
				if (recovery_starts?.has(current_pos)) {
					return -1;
				}
				const char = text[current_pos];
				if (escaped) {
					escaped = false;
				}
				else if (char == '\\') {
					escaped = true;
				}
				else if (char == '<') {
					return -1;
				}
				else if (char == '>') {
					found_angle_end = true;
					current_pos++;
					break;
				}
				current_pos++;
			}
			if (!found_angle_end) {
				return -1;
			}
			destination_end = current_pos;
		}
		else {
			let parenthesis_depth = 0;
			let escaped = false;
			while (current_pos < limit) {
				if (recovery_starts?.has(current_pos)) {
					return -1;
				}
				const char = text[current_pos];
				if (escaped) {
					if (isSpaceOrTab(char)) {
						return -1;
					}
					escaped = false;
				}
				else if (char == '\\') {
					escaped = true;
				}
				else if (isSpaceOrTab(char)) {
					if (parenthesis_depth != 0) {
						return -1;
					}
					break;
				}
				else if ((char == '<') || (char == '>')) {
					return -1;
				}
				else if (char == '(') {
					parenthesis_depth++;
				}
				else if (char == ')') {
					if (parenthesis_depth == 0) {
						if (closing_char == ')') {
							break;
						}
						return -1;
					}
					parenthesis_depth--;
				}
				current_pos++;
			}

			if ((parenthesis_depth != 0) || (!allow_empty && (current_pos == start))) {
				return -1;
			}
			destination_end = current_pos;
		}

		while ((current_pos < limit) && isSpaceOrTab(text[current_pos])) {
			current_pos++;
		}
		if (closing_char ? (text[current_pos] == closing_char) : (current_pos == limit)) {
			return current_pos;
		}

		// an optional title must be separated from the destination by whitespace
		if (current_pos == destination_end) {
			return -1;
		}

		const title_open = text[current_pos];
		let title_close;
		if ((title_open == '"') || (title_open == "'")) {
			title_close = title_open;
		}
		else if (title_open == '(') {
			title_close = ')';
		}
		else {
			return -1;
		}

		current_pos++;
		let found_title_end = false;
		let escaped = false;
		while (current_pos < limit) {
			if (recovery_starts?.has(current_pos)) {
				return -1;
			}
			const char = text[current_pos];
			if (escaped) {
				escaped = false;
			}
			else if (char == '\\') {
				escaped = true;
			}
			else if ((title_open == '(') && (char == '(')) {
				return -1;
			}
			else if (char == title_close) {
				found_title_end = true;
				current_pos++;
				break;
			}
			current_pos++;
		}
		if (!found_title_end) {
			return -1;
		}

		while ((current_pos < limit) && isSpaceOrTab(text[current_pos])) {
			current_pos++;
		}
		if (closing_char ? (text[current_pos] == closing_char) : (current_pos == limit)) {
			return current_pos;
		}
		return -1;
	}

	function parseLineContainer(text, start, end) {
		let current_pos = start;
		let quote_depth = 0;

		// blockquote markers are part of the fence's container
		while (current_pos < end) {
			let marker_pos = current_pos;
			let spaces = 0;
			while ((spaces < 3) && (text[marker_pos] == ' ')) {
				marker_pos++;
				spaces++;
			}
			if (text[marker_pos] != '>') {
				break;
			}
			quote_depth++;
			current_pos = marker_pos + 1;
			if (isSpaceOrTab(text[current_pos])) {
				current_pos++;
			}
		}

		const content_start = current_pos;
		let indent = 0;
		while (isSpaceOrTab(text[current_pos])) {
			indent = (text[current_pos] == '\t') ? (indent + 4 - (indent % 4)) : (indent + 1);
			current_pos++;
		}
		let has_list_marker = false;
		let list_indent = 0;
		const list_indents = [];
		let marker_column = indent;
		while (current_pos < end) {
			const marker_start = current_pos;
			let marker_end = marker_start;
			if (/[-+*]/.test(text[marker_end] ?? '')) {
				marker_end++;
			}
			else if (/\d/.test(text[marker_end] ?? '')) {
				while ((marker_end < end) && /\d/.test(text[marker_end]) && ((marker_end - marker_start) < 9)) {
					marker_end++;
				}
				if ((text[marker_end] != '.') && (text[marker_end] != ')')) {
					marker_end = marker_start;
				}
				else {
					marker_end++;
				}
			}
			if (marker_end == marker_start) {
				break;
			}

			if (marker_end == end) {
				has_list_marker = true;
				marker_column += marker_end - marker_start;
				list_indent = marker_column + 1;
				list_indents.push(list_indent);
				current_pos = marker_end;
				break;
			}
			if (!isSpaceOrTab(text[marker_end])) {
				break;
			}
			has_list_marker = true;
			marker_column += marker_end - marker_start;
			while (isSpaceOrTab(text[marker_end])) {
				marker_column = (text[marker_end] == '\t') ? (marker_column + 4 - (marker_column % 4)) : (marker_column + 1);
				marker_end++;
			}
			current_pos = marker_end;
			list_indent = marker_column;
			list_indents.push(list_indent);
		}
		return {
			quote_depth: quote_depth,
			has_list_marker: has_list_marker,
			indent: indent,
			list_indent: list_indent,
			list_indents: list_indents,
			in_list: has_list_marker,
			content_position: current_pos,
			is_blank: text.substring(content_start, end).trim() == ''
		};
	}

	function parseFenceLine(text, start, end, container = null) {
		const line_container = container ?? parseLineContainer(text, start, end);
		let current_pos = line_container.content_position;
		const fence_char = text[current_pos];
		if ((fence_char != '`') && (fence_char != '~')) {
			return null;
		}
		const fence_start = current_pos;
		while (text[current_pos] == fence_char) {
			current_pos++;
		}
		const fence_length = current_pos - fence_start;
		if (fence_length < 3) {
			return null;
		}

		const remainder = text.substring(current_pos, end);
		const is_closing = /^[ \t]*$/.test(remainder);
		if (!is_closing && (fence_char == '`') && remainder.includes('`')) {
			return null;
		}
		return {
			start: start,
			quote_depth: line_container.quote_depth,
			has_list_marker: line_container.has_list_marker,
			indent: line_container.indent,
			list_indent: line_container.list_indent,
			in_list: line_container.in_list,
			fence_char: fence_char,
			fence_length: fence_length,
			is_closing: is_closing
		};
	}

	function canOpenFence(candidate) {
		return (candidate.indent <= 3) || (candidate.in_list && candidate.inherited_list);
	}

	function fenceContainerEnded(opening, container) {
		if (container.quote_depth < opening.quote_depth) {
			return true;
		}
		if (container.is_blank) {
			return false;
		}
		return opening.in_list &&
			(container.quote_depth == opening.quote_depth) &&
			(container.indent < opening.list_indent);
	}

	function fenceCloses(opening, candidate) {
		if (!candidate.is_closing || (candidate.fence_char != opening.fence_char) ||
			(candidate.fence_length < opening.fence_length) ||
			(candidate.quote_depth != opening.quote_depth)) {
			return false;
		}
		if (!opening.in_list) {
			return !candidate.has_list_marker && (candidate.indent <= 3);
		}
		return !candidate.has_list_marker &&
			(candidate.indent >= opening.list_indent) &&
			(candidate.indent <= (opening.list_indent + 3));
	}

	function protectFencedCode(text, placeholders) {
		let result = '';
		let last_pos = 0;
		let opening = null;
		let active_lists = [];
		let line_start = 0;

		while (line_start <= text.length) {
			const newline_pos = text.indexOf('\n', line_start);
			const line_end = (newline_pos == -1) ? text.length : newline_pos;
			const content_end = ((line_end > line_start) && (text[line_end - 1] == '\r')) ? (line_end - 1) : line_end;
			const container = parseLineContainer(text, line_start, content_end);
			const candidate = parseFenceLine(text, line_start, content_end, container);

			// carry list indentation onto continuation lines and nested list items
			let line_lists = [];
			let inherited_list = false;
			if (container.is_blank && ((active_lists.length == 0) ||
				(active_lists[0].quote_depth == container.quote_depth))) {
				line_lists = active_lists;
				inherited_list = line_lists.length > 0;
			}
			else {
				line_lists = active_lists.filter((item) => {
					return (item.quote_depth == container.quote_depth) && (item.indent <= container.indent);
				});
				inherited_list = line_lists.length > 0;
				if ((container.indent <= 3) || inherited_list) {
					for (const indent of container.list_indents) {
						line_lists.push({ quote_depth: container.quote_depth, indent: indent });
					}
				}
			}
			if (candidate && (line_lists.length > 0)) {
				const line_list = line_lists[line_lists.length - 1];
				candidate.in_list = true;
				candidate.inherited_list = inherited_list;
				candidate.list_indent = line_list.indent;
				candidate.list_contexts = line_lists.slice();
			}

			if (opening && fenceContainerEnded(opening, container)) {
				let block_end = line_start - 1;
				if ((block_end > opening.start) && (text[block_end - 1] == '\r')) {
					block_end--;
				}
				result += text.substring(last_pos, opening.start);
				result += placeholders.add('code_block', text.substring(opening.start, block_end));
				last_pos = block_end;
				opening = null;
			}

			if (!opening && candidate && canOpenFence(candidate)) {
				opening = candidate;
			}
			else if (opening && candidate && fenceCloses(opening, candidate)) {
				result += text.substring(last_pos, opening.start);
				result += placeholders.add('code_block', text.substring(opening.start, line_end));
				last_pos = line_end;
				opening = null;
			}
			// code contents are opaque, so keep their opening list context unchanged
			if (opening?.in_list) {
				active_lists = opening.list_contexts;
			}
			else {
				active_lists = line_lists;
			}

			if (newline_pos == -1) {
				break;
			}
			line_start = newline_pos + 1;
		}
		if (opening) {
			result += text.substring(last_pos, opening.start);
			result += placeholders.add('code_block', text.substring(opening.start));
			last_pos = text.length;
		}

		return result + text.substring(last_pos);
	}

	function protectReferenceDefinitions(text, placeholders) {
		const reference_start_regex = /^[ \t]{0,3}\[[^\]\r\n]+\]:[ \t]*/gm;
		let result = '';
		let last_pos = 0;
		let match;

		while ((match = reference_start_regex.exec(text)) != null) {
			const target_start = reference_start_regex.lastIndex;
			const target_limit = lineEnd(text, target_start);
			const target_end = findMarkdownTargetEnd(text, target_start, target_limit, null, false);
			if (target_end != target_limit) {
				continue;
			}

			result += text.substring(last_pos, match.index);
			result += placeholders.add('reference', text.substring(match.index, target_limit));
			last_pos = target_limit;
			reference_start_regex.lastIndex = target_limit;
		}

		return result + text.substring(last_pos);
	}

	function protectCodeSpans(text, placeholders) {
		const runs = [];
		let current_pos = 0;
		while ((current_pos = text.indexOf('`', current_pos)) != -1) {
			const run_start = current_pos;
			while (text[current_pos] == '`') {
				current_pos++;
			}
			runs.push({
				start: run_start,
				end: current_pos,
				length: current_pos - run_start,
				escaped: isEscaped(text, run_start)
			});
		}

		const next_run = [];
		const next_by_length = new Map();
		for (let i = runs.length - 1; i >= 0; i--) {
			next_run[i] = next_by_length.get(runs[i].length) ?? -1;
			next_by_length.set(runs[i].length, i);
		}

		let result = '';
		let last_pos = 0;
		let run_index = 0;
		while (run_index < runs.length) {
			if (runs[run_index].escaped) {
				run_index++;
				continue;
			}
			const closing_index = next_run[run_index];
			if (closing_index == -1) {
				run_index++;
				continue;
			}

			const opening = runs[run_index];
			const closing = runs[closing_index];
			result += text.substring(last_pos, opening.start);
			result += placeholders.add('code_inline', text.substring(opening.start, closing.end));
			last_pos = closing.end;
			run_index = closing_index + 1;
		}

		return result + text.substring(last_pos);
	}

	function findInlineLinkCandidates(text) {
		const candidates = new Map();
		const starts = new Set();
		let current_pos = 0;
		const brackets = [];

		while (current_pos < text.length) {
			const char = text[current_pos];
			if ((char == '\r') || (char == '\n')) {
				brackets.length = 0;
				current_pos++;
				continue;
			}
			if ((char == '[') && !isEscaped(text, current_pos)) {
				brackets.push(current_pos);
				current_pos++;
				continue;
			}
			if ((char != ']') || isEscaped(text, current_pos) || (brackets.length == 0)) {
				current_pos++;
				continue;
			}

			const label_start = brackets.pop();
			if (text[current_pos + 1] == '(') {
				candidates.set(current_pos, label_start);
				starts.add(label_start);
			}
			current_pos++;
		}

		return { candidates: candidates, starts: starts };
	}

	function protectInlineLinkTargets(text, placeholders) {
		let result = '';
		let last_pos = 0;
		let minimum_label_start = 0;
		let failed_label_start = -1;
		let retried_containing_label = false;
		let recovering = false;
		const links = findInlineLinkCandidates(text);

		for (const [label_end, label_start] of links.candidates) {
			if (label_start < last_pos) {
				continue;
			}
			if (label_start < minimum_label_start) {
				// retry one containing label, then skip further overlaps to keep this linear
				if (retried_containing_label || (label_start >= failed_label_start)) {
					continue;
				}
				retried_containing_label = true;
			}

			const target_start = label_end + 2;
			const target_limit = lineEnd(text, target_start);
			const recovery_starts = recovering ? links.starts : null;
			const target_end = findMarkdownTargetEnd(text, target_start, target_limit, ')', true, recovery_starts);
			if (target_end == -1) {
				// later candidates whose labels overlap this target cannot be separate links
				minimum_label_start = Math.max(minimum_label_start, target_start);
				failed_label_start = label_start;
				recovering = true;
				continue;
			}

			result += text.substring(last_pos, label_end + 1);
			result += placeholders.add('link_target', text.substring(label_end + 1, target_end + 1));
			last_pos = target_end + 1;
			minimum_label_start = last_pos;
			failed_label_start = -1;
			retried_containing_label = false;
			recovering = false;
		}

		return result + text.substring(last_pos);
	}

	function markInlineLinks(text, placeholders, text_open, url_open, span_close) {
		let result = '';
		let last_pos = 0;
		let current_pos = 0;
		const brackets = [];

		while (current_pos < text.length) {
			const char = text[current_pos];
			if ((char == '\r') || (char == '\n')) {
				brackets.length = 0;
				current_pos++;
				continue;
			}
			if ((char == '[') && !isEscaped(text, current_pos)) {
				brackets.push(current_pos);
				current_pos++;
				continue;
			}
			if ((char != ']') || isEscaped(text, current_pos) || (brackets.length == 0)) {
				current_pos++;
				continue;
			}

			const label_start = brackets.pop();
			const target = placeholders.tokenAt(text, current_pos + 1, 'link_target');
			if (!target) {
				current_pos++;
				continue;
			}

			result += text.substring(last_pos, label_start);
			result += text_open + text.substring(label_start, current_pos + 1) + span_close;
			result += url_open + text.substring(current_pos + 1, target.end) + span_close;
			last_pos = target.end;
			current_pos = target.end;
			brackets.length = 0;
		}

		return result + text.substring(last_pos);
	}

	function findHTMLTagEnd(text, start) {
		if (text.startsWith('<!--', start)) {
			const comment_end = text.indexOf('-->', start + 4);
			return (comment_end == -1) ? -1 : (comment_end + 2);
		}
		if (text.startsWith('<![CDATA[', start)) {
			const cdata_end = text.indexOf(']]>', start + 9);
			return (cdata_end == -1) ? -1 : (cdata_end + 2);
		}
		if (text.startsWith('<?', start)) {
			const instruction_end = text.indexOf('?>', start + 2);
			return (instruction_end == -1) ? -1 : (instruction_end + 1);
		}
		if (text.startsWith('<!', start)) {
			return text.indexOf('>', start + 2);
		}

		let current_pos = start + 1;
		if (text[current_pos] == '/') {
			current_pos++;
		}
		if (!/[A-Za-z]/.test(text[current_pos] ?? '')) {
			return -1;
		}
		while (/[A-Za-z0-9:-]/.test(text[current_pos] ?? '')) {
			current_pos++;
		}
		if (!isSpaceOrTab(text[current_pos]) && (text[current_pos] != '/') && (text[current_pos] != '>')) {
			return -1;
		}

		let quote = null;
		while (current_pos < text.length) {
			const char = text[current_pos];
			if ((char == '\r') || (char == '\n')) {
				return -1;
			}
			if (quote) {
				if (char == quote) {
					quote = null;
				}
			}
			else if ((char == '"') || (char == "'")) {
				quote = char;
			}
			else if (char == '<') {
				return -1;
			}
			else if (char == '>') {
				return current_pos;
			}
			current_pos++;
		}
		return -1;
	}

	function protectHTMLTags(text, placeholders) {
		let result = '';
		let last_pos = 0;
		let current_pos = 0;

		while ((current_pos = text.indexOf('<', current_pos)) != -1) {
			if (isEscaped(text, current_pos)) {
				current_pos++;
				continue;
			}
			const tag_end = findHTMLTagEnd(text, current_pos);
			if (tag_end == -1) {
				if (text.startsWith('<!', current_pos) || text.startsWith('<?', current_pos)) {
					result += text.substring(last_pos, current_pos);
					result += placeholders.add('html_tag', text.substring(current_pos));
					last_pos = text.length;
					break;
				}
				current_pos++;
				continue;
			}

			result += text.substring(last_pos, current_pos);
			result += placeholders.add('html_tag', text.substring(current_pos, tag_end + 1));
			last_pos = tag_end + 1;
			current_pos = tag_end + 1;
		}

		return result + text.substring(last_pos);
	}

	function protectURLs(text, placeholders) {
		const url_regex = /\bhttps?:\/\/[^\s<()]+(?:\([^\s<()]*\)[^\s<()]*)*/g;
		return text.replace(url_regex, (match) => {
			let url = match;
			let suffix = '';

			function trimSuffix(length) {
				suffix = url.substring(url.length - length) + suffix;
				url = url.substring(0, url.length - length);
			}

			const trailing = url.match(/[*_.,!?;:]+$/);
			if (trailing) {
				trimSuffix(trailing[0].length);
			}
			return placeholders.add('url', url) + suffix;
		});
	}

	function protectAutolinks(text, placeholders) {
		const autolink_regex = /<(?:https?:\/\/[^<>\s]+|[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9.-]+)>/g;
		return text.replace(autolink_regex, (match) => placeholders.add('url', match));
	}

	function markDelimited(text, delimiter, open_marker, close_marker, can_open, can_close) {
		let result = '';
		let last_pos = 0;
		let opening_pos = -1;
		let current_pos = 0;
		let previous_pos = 0;

		while ((current_pos = text.indexOf(delimiter, current_pos)) != -1) {
			if ((opening_pos != -1) && /[\r\n]/.test(text.substring(previous_pos, current_pos))) {
				opening_pos = -1;
			}
			if (isEscaped(text, current_pos)) {
				current_pos += delimiter.length;
				previous_pos = current_pos;
				continue;
			}

			if (opening_pos == -1) {
				if (can_open(text, current_pos)) {
					opening_pos = current_pos;
				}
			}
			else if (can_close(text, current_pos)) {
				result += text.substring(last_pos, opening_pos);
				result += open_marker;
				result += text.substring(opening_pos + delimiter.length, current_pos);
				result += close_marker;
				last_pos = current_pos + delimiter.length;
				opening_pos = -1;
			}
			else if (can_open(text, current_pos)) {
				// prefer a later viable opener over an unmatched earlier delimiter
				opening_pos = current_pos;
			}
			current_pos += delimiter.length;
			previous_pos = current_pos;
		}

		return result + text.substring(last_pos);
	}

	function isWordCharacter(char) {
		return !!char && /[\p{L}\p{N}_]/u.test(char);
	}

	function markItalics(text, open_marker, close_marker) {
		return markDelimited(
			text,
			'_',
			open_marker,
			close_marker,
			(value, position) => {
				return !isWordCharacter(value[position - 1]) && !isWhitespace(value[position + 1]) && (value[position + 1] != '_');
			},
			(value, position) => {
				return !isWhitespace(value[position - 1]) && (value[position - 1] != '_') && !isWordCharacter(value[position + 1]);
			}
		);
	}

	function markBold(text, open_marker, close_marker) {
		return markDelimited(
			text,
			'**',
			open_marker,
			close_marker,
			(value, position) => {
				return (value[position - 1] != '*') && !isWhitespace(value[position + 2]) && (value[position + 2] != '*');
			},
			(value, position) => {
				return (value[position - 1] != '*') && !isWhitespace(value[position - 1]) && (value[position + 2] != '*');
			}
		);
	}

	function formatEditorHTML(text) {
		const quote_regex = /^ {0,3}>.*$/gm;
		const header_regex = /^ {0,3}#{1,6}(?:[ \t]+.*)?$/gm;
		const divider_regex = /^ {0,3}(?:-[ \t]*){3,}(?=\r?$)/gm;
		const username_regex = /@([a-zA-Z0-9_@-]+(?:\.[a-zA-Z0-9_@-]+)*)/g;

		let s = String(text);
		const placeholders = createPlaceholderStore(s);

		// protect atomic Markdown ranges before looking for formatting delimiters
		s = protectFencedCode(s, placeholders);
		s = protectReferenceDefinitions(s, placeholders);
		s = protectCodeSpans(s, placeholders);
		s = protectInlineLinkTargets(s, placeholders);
		s = protectAutolinks(s, placeholders);
		s = protectHTMLTags(s, placeholders);
		s = protectURLs(s, placeholders);

		// formatting markers stay as placeholders until every source regex has run
		const italic_open = placeholders.add('markup', '<span class="editor_italic">_');
		const italic_close = placeholders.add('markup', '_</span>');
		const bold_open = placeholders.add('markup', '<span class="editor_bold">**');
		const bold_close = placeholders.add('markup', '**</span>');
		const quote_open = placeholders.add('markup', '<span class="editor_quote">');
		const header_open = placeholders.add('markup', '<span class="editor_header">');
		const divider_open = placeholders.add('markup', '<span class="editor_divider">');
		const username_open = placeholders.add('markup', '<span class="editor_username">');
		const link_text_open = placeholders.add('markup', '<span class="editor_link_text">');
		const link_url_open = placeholders.add('markup', '<span class="editor_link_url">');
		const span_close = placeholders.add('markup', '</span>');

		s = markItalics(s, italic_open, italic_close);
		s = markBold(s, bold_open, bold_close);
		s = s.replace(quote_regex, (match) => `${quote_open}${match}${span_close}`);
		s = s.replace(header_regex, (match) => `${header_open}${match}${span_close}`);
		s = s.replace(divider_regex, (match) => `${divider_open}${match}${span_close}`);
		s = s.replace(username_regex, (match) => `${username_open}${match}${span_close}`);
		s = markInlineLinks(s, placeholders, link_text_open, link_url_open, span_close);

		// escape all remaining source once, then restore trusted markup and escaped atoms
		s = escapeEditorHTML(s);
		return placeholders.restore(s);
	}

	function applyStyles() {
		if (isIgnoringInput) return;
		if (checkLength()) return;

		const editor = document.getElementById(textBoxID);
		let saved = saveSelection(editor);
		if (!saved || (saved.character == '')) {
			debugLog("no saved");
		}

		let s = formatEditorHTML(editorPlainText(editor));

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

		const last_username_regex = /@([a-zA-Z0-9_@-]+(?:\.[a-zA-Z0-9_@-]+)*)$/g;
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

	return {
		init: init,
		getMarkdownByID: getMarkdownByID,
		formatEditorHTML: formatEditorHTML
	};
})();
