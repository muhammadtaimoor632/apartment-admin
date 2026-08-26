jQuery(document).ready(function ($) {
    var formSelect = $('#fdp_mapped_form_id');
    var fieldsContainer = $('#fdp_form_fields_list');
    var cachedFields = [];

    var cmInstances = {};

    function initEditor(id) {
        var textarea = document.getElementById(id);
        if (!textarea) return;

        if (typeof wp !== 'undefined' && wp.codeEditor) {
            var settings = fdp_ajax.cm_settings ? $.extend({}, fdp_ajax.cm_settings) : {};
            var editor = wp.codeEditor.initialize(id, settings);
            cmInstances[id] = editor.codemirror;

            // Sync CodeMirror to textarea on change
            editor.codemirror.on('change', function (cm) {
                cm.save();
            });
        }
    }

    function destroyEditor(id) {
        if (cmInstances[id]) {
            cmInstances[id].toTextArea();
            delete cmInstances[id];
        }
    }

    // Tab Switching for Widget / Code / Preview
    $(document).on('click', '.fdp-tab-btn', function (e) {
        e.preventDefault();
        var btn = $(this);
        var target = btn.attr('data-target');
        var section = btn.closest('.fdp-section-item');

        // Update active buttons
        section.find('.fdp-tab-btn').removeClass('active');
        btn.addClass('active');

        // Update active panes
        section.find('.fdp-editor-pane').hide();
        var pane = section.find('.fdp-editor-pane.' + target);
        pane.show();

        if (target === 'preview') {
            // Get content and show preview
            var textareaId = section.find('.fdp-editor-textarea').attr('id');
            var content = '';
            if (cmInstances[textareaId]) {
                content = cmInstances[textareaId].getValue();
            } else {
                content = section.find('.fdp-editor-textarea').val();
            }
            // Create an iframe to safely isolate the user's HTML/CSS from the WP Admin dashboard
            if (pane.find('iframe').length === 0) {
                pane.html('<iframe style="display:block; width:100%; height:100%; border:none; background:#fff;"></iframe>');
            }
            var iframe = pane.find('iframe')[0];
            var doc = iframe.contentWindow || iframe.contentDocument;
            if (doc.document) doc = doc.document;

            doc.open();
            doc.write(content);
            doc.close();

            // Auto-resize iframe to fit content so it pushes Display Conditions down proportionally
            setTimeout(function () {
                if (doc.body) {
                    var newHeight = doc.body.scrollHeight;
                    if (newHeight < 250) newHeight = 250;
                    iframe.style.height = newHeight + 'px';
                }
            }, 100);
        } else if (target === 'code') {
            // Initialize CM lazily if it hasn't been set up yet (code pane was hidden)
            var textareaId = section.find('.fdp-editor-textarea').attr('id');
            if (textareaId && !cmInstances[textareaId]) {
                initEditor(textareaId);
                setTimeout(function () {
                    if (cmInstances[textareaId]) cmInstances[textareaId].refresh();
                }, 50);
            } else if (cmInstances[textareaId]) {
                cmInstances[textareaId].refresh();
            }
        }
    });

    function populateFieldDropdowns() {
        $('.fdp-field-select').each(function () {
            var select = $(this);
            var currentVal = select.val();
            if (!currentVal) {
                currentVal = select.attr('data-selected');
            }

            var options = '<option value="">' + (select.find('option:first').text() || 'Select Field...') + '</option>';

            $.each(cachedFields, function (index, field) {
                var isSelected = (field.name === currentVal) ? ' selected' : '';
                options += '<option value="' + field.name + '"' + isSelected + '>' + field.label + ' (' + field.name + ')</option>';
            });
            select.html(options);
            select.attr('data-selected', currentVal || '');
        });
        updateValueInputs();
    }

    $(document).on('change', '.fdp-field-select', function () {
        $(this).attr('data-selected', $(this).val());
        updateValueInputs();
    });

    $(document).on('change', '.fdp-value-input', function () {
        $(this).attr('data-value', $(this).val());
    });

    function updateValueInputs() {
        $('.fdp-condition-row').each(function () {
            var row = $(this);
            var select = row.find('.fdp-field-select');
            var fieldName = select.val() || select.attr('data-selected');
            var valueEl = row.find('.fdp-value-input');
            if (!valueEl.length) return;

            var currentValue = valueEl.val();
            if (currentValue === null || currentValue === undefined || currentValue === '') {
                currentValue = valueEl.attr('data-value') || '';
            }
            var inputName = valueEl.attr('name');

            var field = null;
            if (fieldName) {
                $.each(cachedFields, function (i, f) {
                    if (f.name === fieldName) {
                        field = f;
                        return false;
                    }
                });
            }

            if (field && field.options && field.options.length > 0) {
                var optionsHtml = '<select class="fdp-value-input" name="' + inputName + '" data-value="' + currentValue + '">';
                optionsHtml += '<option value="">Select Option...</option>';
                $.each(field.options, function (i, opt) {
                    var val = typeof opt === 'object' ? (opt.value !== undefined ? opt.value : opt.label) : opt;
                    var label = typeof opt === 'object' ? (opt.label !== undefined ? opt.label : opt.value) : opt;
                    var isSelected = (val === currentValue) ? ' selected' : '';
                    optionsHtml += '<option value="' + val + '"' + isSelected + '>' + label + '</option>';
                });
                optionsHtml += '</select>';

                if (valueEl.is('input')) {
                    valueEl.replaceWith(optionsHtml);
                } else {
                    valueEl.html($(optionsHtml).html());
                    valueEl.val(currentValue);
                }
            } else {
                if (valueEl.is('select')) {
                    var inputHtml = '<input type="text" class="fdp-value-input" name="' + inputName + '" value="' + currentValue + '" data-value="' + currentValue + '" placeholder="Value" />';
                    valueEl.replaceWith(inputHtml);
                } else {
                    valueEl.val(currentValue);
                    valueEl.attr('data-value', currentValue);
                }
            }
        });
    }

    function fetchFormFields(formId) {
        if (!formId) {
            fieldsContainer.html('<li>Please select a form to view fields.</li>');
            cachedFields = [];
            populateFieldDropdowns();
            return;
        }

        fieldsContainer.html('<li>Loading fields...</li>');

        $.ajax({
            url: fdp_ajax.ajax_url,
            type: 'POST',
            data: {
                action: 'fdp_get_form_fields',
                form_id: formId,
                nonce: fdp_ajax.nonce
            },
            success: function (response) {
                if (response.success && response.data) {
                    cachedFields = response.data;
                    var html = '';
                    $.each(response.data, function (index, field) {
                        html += '<li style="margin-bottom: 5px;">';
                        html += '<strong>' + field.label + ':</strong> ';
                        html += '<code>[fluent_dynamic field="' + field.name + '"]</code>';
                        html += '</li>';
                    });
                    fieldsContainer.html(html);
                    populateFieldDropdowns();
                } else {
                    fieldsContainer.html('<li>No fields found or error fetching fields.</li>');
                    cachedFields = [];
                    populateFieldDropdowns();
                }
            },
            error: function () {
                fieldsContainer.html('<li>Error fetching fields.</li>');
                cachedFields = [];
                populateFieldDropdowns();
            }
        });
    }

    if (formSelect.val()) {
        fetchFormFields(formSelect.val());
    }

    formSelect.on('change', function () {
        fetchFormFields($(this).val());
    });

    var sectionIndex = $('.fdp-section-item[data-index]').length;

    // Initialize editors for existing sections (only when code pane is visible — skip if widget tab is active)
    $('.fdp-editor-textarea').each(function () {
        if ($(this).closest('#fdp_section_template').length === 0) {
            var $codepane = $(this).closest('.fdp-editor-pane.code');
            // Only init CM when the code pane is actually visible
            if (!$codepane.length || $codepane.is(':visible')) {
                initEditor($(this).attr('id'));
            }
        }
    });

    function reindexSectionsAndConditions() {
        $('#fdp_sections_list > .fdp-section-item').each(function (sIndex) {
            var $section = $(this);
            $section.attr('data-index', sIndex);

            // Update simple section inputs (title, active_tab, widgets_json, content, condition_match)
            $section.find('input, textarea, select').each(function () {
                var name = $(this).attr('name');
                if (!name) return;

                // Skip condition fields as they are handled in the nested loop
                if (name.indexOf('[conditions]') !== -1) {
                    return;
                }

                // Replace fdp_sections[OLD_INDEX] with fdp_sections[sIndex]
                var newName = name.replace(/^fdp_sections\[[^\]]+\]/, 'fdp_sections[' + sIndex + ']');
                $(this).attr('name', newName);
            });

            // Re-index conditions inside this section
            $section.find('.fdp-conditions-list .fdp-condition-row').each(function (cIndex) {
                var $row = $(this);
                $row.find('input, select').each(function () {
                    var name = $(this).attr('name');
                    if (!name) return;

                    // Replace fdp_sections[OLD_SINDEX][conditions][OLD_CINDEX] with fdp_sections[sIndex][conditions][cIndex]
                    var newName = name.replace(/^fdp_sections\[[^\]]+\]\[conditions\]\[[^\]]+\]/, 'fdp_sections[' + sIndex + '][conditions][' + cIndex + ']');
                    $(this).attr('name', newName);
                });
            });
        });

        // Update the global sectionIndex counter so new sections use the correct next index
        sectionIndex = $('#fdp_sections_list > .fdp-section-item').length;
    }

    $('#fdp_add_section').on('click', function () {
        var template = $('#fdp_section_template').html();
        template = template.replace(/{INDEX}/g, sectionIndex);

        var newSection = $('<div class="fdp-section-item" data-index="' + sectionIndex + '">' + template + '</div>');
        $('#fdp_sections_list').append(newSection);

        var newTextareaId = 'fdp_section_content_' + sectionIndex;
        // Only initialize CodeMirror if the code pane will be visible (i.e. code tab is active)
        var newActiveTab = newSection.find('.fdp-active-tab-input').val() || 'widget';
        if (newActiveTab !== 'widget') {
            initEditor(newTextareaId);
        }

        populateFieldDropdowns();

        // Initialize widget pane for new section
        var $widgetPane = newSection.find('.fdp-editor-pane.widget');
        if ($widgetPane.length) {
            fdpInitSortable($widgetPane.find('.fdp-widget-list'));
        }

        sectionIndex++;
        reindexSectionsAndConditions();
    });

    $(document).on('click', '.fdp-remove-section', function (e) {
        e.preventDefault();
        if (confirm('Are you sure you want to remove this section?')) {
            var textarea = $(this).closest('.fdp-section-item').find('.fdp-editor-textarea');
            if (textarea.length) {
                destroyEditor(textarea.attr('id'));
            }
            $(this).closest('.fdp-section-item').remove();
            reindexSectionsAndConditions();
        }
    });

    $(document).on('click', '.fdp-duplicate-section', function (e) {
        e.preventDefault();
        var $original = $(this).closest('.fdp-section-item');

        // Ensure widget builder is serialized
        var $wPane = $original.find('.fdp-editor-pane.widget');
        if ($wPane.length) {
            var $list = $wPane.find('.fdp-widget-list');
            var wData = fdpCollectFromList($list);
            $wPane.find('.fdp-widgets-json-store').val(JSON.stringify(wData));
        }

        // Destroy CodeMirror on original temporarily
        var textarea = $original.find('.fdp-editor-textarea');
        var wasCodeMirrorActive = false;
        if (textarea.length && textarea.next('.CodeMirror').length) {
            wasCodeMirrorActive = true;
            destroyEditor(textarea.attr('id'));
        }

        var $clone = $original.clone();

        // Restore CodeMirror on original
        if (wasCodeMirrorActive) {
            initEditor(textarea.attr('id'));
        }

        // Update Title
        var $titleInput = $clone.find('.fdp-section-title-input');
        if ($titleInput.length) {
            var oldTitle = $titleInput.val() || 'Section';
            $titleInput.val(oldTitle + ' (duplicate)');
            $clone.find('.fdp-section-title-label').text($titleInput.val());
        }

        // Generate new ID for textarea
        $clone.attr('data-index', sectionIndex);
        var newTextareaId = 'fdp_section_content_' + sectionIndex;
        $clone.find('.fdp-editor-textarea').attr('id', newTextareaId).show().removeClass('CodeMirror-applied');
        $clone.find('.CodeMirror').remove();

        $original.after($clone);

        // Init sortable and load widgets for clone
        var $cloneWPane = $clone.find('.fdp-editor-pane.widget');
        if ($cloneWPane.length) {
            fdpInitSortable($cloneWPane.find('.fdp-widget-list'));
            var wJson = $cloneWPane.find('.fdp-widgets-json-store').val();
            $cloneWPane.find('.fdp-widget-list').empty();
            if (wJson && wJson !== '[]') {
                fdpLoadWidgetPane($cloneWPane);
            }
        }

        var newActiveTab = $clone.find('.fdp-active-tab-input').val() || 'widget';
        if (newActiveTab !== 'widget') {
            initEditor(newTextareaId);
        }

        populateFieldDropdowns();
        sectionIndex++;
        reindexSectionsAndConditions();
    });

    $(document).on('click', '.fdp-section-toggle', function () {
        var $header = $(this).closest('.fdp-section-header');
        var $body = $header.siblings('.fdp-section-body');
        var $icon = $(this).find('.fdp-toggle-icon');

        $body.slideToggle(200, function () {
            if ($body.is(':visible')) {
                $icon.css('transform', 'rotate(0deg)');
                // Refresh CodeMirror when section becomes visible so it sizes correctly
                $body.find('.CodeMirror').each(function (i, el) {
                    if (el.CodeMirror) {
                        el.CodeMirror.refresh();
                    }
                });
            } else {
                $icon.css('transform', 'rotate(-90deg)');
            }
        });
    });

    $(document).on('click', '.fdp-add-condition', function () {
        var section = $(this).closest('.fdp-section-item');
        var sIndex = section.attr('data-index');
        var list = section.find('.fdp-conditions-list');
        var cIndex = list.find('.fdp-condition-row').length;

        var row = '<div class="fdp-condition-row">' +
            '<select class="fdp-field-select" name="fdp_sections[' + sIndex + '][conditions][' + cIndex + '][field]" data-selected="" style="width:150px;">' +
            '<option value="">Select Field...</option>' +
            '</select>' +
            '<select name="fdp_sections[' + sIndex + '][conditions][' + cIndex + '][operator]">' +
            '<option value="equals">Equals</option>' +
            '<option value="not_equals">Not Equals</option>' +
            '<option value="greater_than">Greater Than</option>' +
            '<option value="less_than">Less Than</option>' +
            '<option value="contains">Contains</option>' +
            '</select>' +
            '<input type="text" class="fdp-value-input" name="fdp_sections[' + sIndex + '][conditions][' + cIndex + '][value]" value="" data-value="" placeholder="Value" />' +
            '<span class="fdp-remove-condition" title="Remove rule">&times;</span>' +
            '</div>';

        list.append(row);
        populateFieldDropdowns();
        reindexSectionsAndConditions();
    });

    $(document).on('click', '.fdp-remove-condition', function () {
        $(this).closest('.fdp-condition-row').remove();
        reindexSectionsAndConditions();
    });

    if ($.fn.sortable) {
        $('#fdp_sections_list').sortable({
            handle: '.fdp-section-header',
            placeholder: 'sortable-placeholder',
            forcePlaceholderSize: true,
            start: function (event, ui) {
                // Destroy editor before sorting to prevent TinyMCE iframe crash
                var textarea = ui.item.find('.fdp-editor-textarea');
                if (textarea.length) {
                    destroyEditor(textarea.attr('id'));
                }
            },
            stop: function (event, ui) {
                // Re-initialize editor after sorting
                var textarea = ui.item.find('.fdp-editor-textarea');
                if (textarea.length) {
                    initEditor(textarea.attr('id'));
                }
                reindexSectionsAndConditions();
            }
        });
    }

    // Trigger save on form submit to ensure CodeMirror content is synced
    $('form#post').on('submit', function () {
        // Re-index all fields to ensure clean Sequential names
        reindexSectionsAndConditions();
        // First serialize any widget builder panes → generate HTML into content textareas
        fdpSerializeAll();
        // Then sync all CodeMirror instances
        $.each(cmInstances, function (id, cm) {
            cm.save();
        });
    });


    // ================================================================
    //  FDP WIDGET BUILDER
    // ================================================================

    // Widget type definitions
    var fdpWidgetTypes = {
        accordion: {
            label: 'Accordion',
            icon: '&#x1F4C2;',
            iconText: '📂',
            color: '#1a73e8',
            desc: 'Collapsible step with title, optional video link, and child widgets'
        },
        youtube_video: {
            label: 'YouTube Video',
            icon: '&#x25B6;',
            iconText: '▶',
            color: '#c9312a',
            desc: 'A link that opens a YouTube video in a full-screen popup'
        },
        google_map: {
            label: 'Google Map',
            icon: '&#x1F4CD;',
            iconText: '📍',
            color: '#0f9d58',
            desc: 'A styled "View on Google Maps" link'
        },
        instruction_row: {
            label: 'Instruction Row',
            icon: '&#x1F5BC;',
            iconText: '🖼',
            color: '#7c3aed',
            desc: 'Bullet text on left, optional image on right'
        },
        rich_text: {
            label: 'Rich Text',
            icon: 'T',
            iconText: 'T',
            color: '#d97706',
            desc: 'A paragraph or text block (shortcodes supported)'
        },
        divider: {
            label: 'Divider',
            icon: '&mdash;',
            iconText: '—',
            color: '#6b7280',
            desc: 'A horizontal separator line'
        },
        notice: {
            label: 'Notice Box',
            icon: '&#9888;',
            iconText: '⚠',
            color: '#eab308',
            desc: 'A styled notice box (info, success, warning, error)'
        },
        popup: {
            label: 'Dynamic Popup',
            icon: '&#x1F5D4;',
            iconText: '🗔',
            color: '#ec4899',
            desc: 'A dynamic popup modal with triggers and delay'
        }
    };

    var fdpRootTypes = ['accordion', 'youtube_video', 'google_map', 'instruction_row', 'rich_text', 'divider', 'notice', 'popup'];
    var fdpChildTypes = ['instruction_row', 'youtube_video', 'google_map', 'rich_text', 'divider', 'notice'];

    // State
    var fdpPaletteTarget = null;
    var fdpPaletteIsChild = false;
    var fdpLastTextarea = null;
    var fdpLastCursorPos = 0;

    // ── Escape helpers ────────────────────────────────────────────
    function fdpEscHtml(s) {
        return String(s)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }
    function fdpEscAttr(s) {
        return String(s)
            .replace(/&/g, '&amp;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#x27;');
    }

    // ── HTML generation from widget objects ───────────────────────
    function fdpWidgetToHtml(w) {
        if (!w || !w.type) return '';
        var h = '';

        if (w.type === 'accordion') {
            h += '<div class="fdp-accordion-item">\n';
            h += '  <button class="fdp-accordion-header">' + (w.title || '') + '</button>\n';
            h += '  <div class="fdp-accordion-panel">\n';
            h += '    <div class="fdp-panel-content">\n';
            if (w.video_url) {
                var vUrlEscaped = fdpEscAttr(w.video_url);
                h += '      <div class="fdp-step-video-bar"><span class="fdp-video-text-wrapper">';
                h += '<a href="#" class="fdp-video-link" data-video-url="' + vUrlEscaped + '">Click here</a>&nbsp;to watch the video</span>';
                h += '<a href="#" class="fdp-video-link" data-video-url="' + vUrlEscaped + '" style="display: inline-flex; align-items: center; border-bottom: none;">';
                h += '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="#d32f2f"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 14.5v-9l6 4.5-6 4.5z"/></svg>';
                h += '</a>';
                h += '</div>\n';
            }
            if (w.children && w.children.length) {
                w.children.forEach(function (child) { h += fdpWidgetToHtml(child); });
            }
            h += '    </div>\n  </div>\n</div>\n';

        } else if (w.type === 'instruction_row') {
            h += '<div class="fdp-instruction-row">\n';
            h += '  <div class="fdp-text-column">' + (w.text || '');
            if (w.map_url) {
                h += '\n    <br><a href="' + fdpEscAttr(w.map_url) + '" target="_blank" class="fdp-map-link">View on Google Maps</a>';
            }
            if (w.video_url) {
                var vUrlEscaped = fdpEscAttr(w.video_url);
                h += '\n    <br><div style="display: flex; justify-content: space-between; align-items: center; margin-top: 8px;"><span><a href="#" class="fdp-video-link" data-video-url="' + vUrlEscaped + '">Watch Video</a></span>';
                h += '<a href="#" class="fdp-video-link" data-video-url="' + vUrlEscaped + '" style="display: inline-flex; align-items: center; border-bottom: none;">';
                h += '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="#d32f2f"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 14.5v-9l6 4.5-6 4.5z"/></svg></a></div>';
            }
            h += '\n  </div>\n  <div class="fdp-image-column">';
            if (w.image_url) {
                h += '\n    <div class="fdp-image-container"><img src="' + fdpEscAttr(w.image_url) + '" alt=""></div>';
            }
            h += '\n  </div>\n</div>\n';

        } else if (w.type === 'youtube_video') {
            var vUrl = w.video_url || '';
            var urlMatch = vUrl.match(/https?:\/\/(?:www\.)?(?:youtube\.com\/(?:watch\?v=|embed\/|shorts\/)|youtu\.be\/)[a-zA-Z0-9_-]+/);
            if (urlMatch) {
                vUrl = urlMatch[0];
            }
            var embedUrl = vUrl;
            if (vUrl.indexOf('youtu.be/') !== -1) {
                var vId = vUrl.split('youtu.be/')[1].split('?')[0].split('&')[0];
                embedUrl = 'https://www.youtube.com/embed/' + vId;
            } else if (vUrl.indexOf('youtube.com/watch') !== -1) {
                var parts = vUrl.split('v=');
                if (parts.length > 1) {
                    var vId = parts[1].split('&')[0];
                    embedUrl = 'https://www.youtube.com/embed/' + vId;
                }
            } else if (vUrl.indexOf('youtube.com/shorts/') !== -1) {
                var vId = vUrl.split('youtube.com/shorts/')[1].split('?')[0].split('&')[0];
                embedUrl = 'https://www.youtube.com/embed/' + vId;
            }
            h += '<div class="fdp-widget-video" style="width: 100%; max-width: 800px; display: block; margin: 0 auto; padding: 20px 0;">';
            h += '  <div class="fdp-video-embed fdp-landscape">';
            if (embedUrl) {
                h += '    <iframe src="' + fdpEscAttr(embedUrl) + '" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture" allowfullscreen></iframe>';
            }
            h += '  </div>';
            h += '</div>\n';

        } else if (w.type === 'google_map') {
            var mapLabel = (w.label && w.label.trim()) ? w.label : 'View on Google Maps';
            h += '<div class="fdp-widget-map"><a href="' + fdpEscAttr(w.map_url || '') + '" target="_blank" class="fdp-map-link">';
            h += '&#x1F4CD; ' + fdpEscHtml(mapLabel) + '</a></div>\n';

        } else if (w.type === 'rich_text') {
            h += '<div class="fdp-widget-text">' + (w.text || '') + '</div>\n';

        } else if (w.type === 'divider') {
            h += '<hr class="fdp-divider">\n';

        } else if (w.type === 'notice') {
            var noticeType = w.notice_type || 'info';
            h += '<div class="fdp-notice fdp-notice-' + noticeType + '">\n';
            if (w.title) {
                h += '  <h4 class="fdp-notice-title">' + fdpEscHtml(w.title) + '</h4>\n';
            }
            h += '  <div class="fdp-notice-text">' + (w.text || '') + '</div>\n';
            h += '</div>\n';

        } else if (w.type === 'popup') {
            var trigger = w.trigger || 'page_load';
            var delay = w.delay || '0';
            h += '<div class="fdp-dynamic-popup-modal" id="fdp-dynamic-popup-modal" aria-modal="true" role="dialog" data-trigger="' + fdpEscAttr(trigger) + '" data-delay="' + fdpEscAttr(delay) + '">\n';
            h += '  <div class="fdp-modal-inner fdp-dynamic-popup-inner">\n';
            h += '    <button class="fdp-modal-close fdp-popup-close-btn" aria-label="Close popup">&times; Close</button>\n';
            h += '    <div class="fdp-popup-content-wrap">\n';
            // We use simple line-break conversion similar to wpautop for raw text
            var contentHtml = (w.text || '').replace(/\n/g, '<br>');
            h += '      ' + (w.text || '') + '\n';
            h += '    </div>\n';
            h += '  </div>\n';
            h += '</div>\n';
        }
        return h;
    }

    function fdpWidgetsToHtml(widgets) {
        var h = '';
        (widgets || []).forEach(function (w) { h += fdpWidgetToHtml(w); });
        return h;
    }

    // ── Collect widget data from a DOM list ───────────────────────
    function fdpCollectFromList($list) {
        var widgets = [];
        $list.children('.fdp-widget-card').each(function () {
            var $card = $(this);
            var type = $card.attr('data-type');
            var w = { type: type };
            var $body = $card.find('> .fdp-widget-card-body');

            switch (type) {
                case 'accordion':
                    w.title = $body.find('> .fdp-wfield .fdp-wf-title').val() || '';
                    w.video_url = $body.find('> .fdp-wfield .fdp-wf-video-url').val() || '';
                    w.children = fdpCollectFromList($body.find('> .fdp-children-field .fdp-child-list'));
                    break;
                case 'instruction_row':
                    w.text = $body.find('.fdp-wf-text').val() || '';
                    w.map_url = $body.find('.fdp-wf-map-url').val() || '';
                    w.video_url = $body.find('.fdp-wf-video-url').val() || '';
                    w.image_url = $body.find('.fdp-wf-image-url').val() || '';
                    break;
                case 'youtube_video':
                    w.video_url = $body.find('.fdp-wf-video-url').val() || '';
                    break;
                case 'google_map':
                    w.map_url = $body.find('.fdp-wf-map-url').val() || '';
                    w.label = $body.find('.fdp-wf-map-label').val() || '';
                    break;
                case 'rich_text':
                    w.text = $body.find('.fdp-wf-text').val() || '';
                    break;
                case 'notice':
                    w.notice_type = $body.find('.fdp-wf-notice-type').val() || 'info';
                    w.title = $body.find('.fdp-wf-title').val() || '';
                    w.text = $body.find('.fdp-wf-text').val() || '';
                    break;
                case 'popup':
                    w.trigger = $body.find('.fdp-wf-trigger').val() || 'page_load';
                    w.delay = $body.find('.fdp-wf-delay').val() || '0';
                    w.text = $body.find('.fdp-wf-text').val() || '';
                    break;
            }
            widgets.push(w);
        });
        return widgets;
    }

    // ── Create a widget card jQuery element ───────────────────────
    function fdpCreateCard(type, data, isChild) {
        data = data || {};
        var info = fdpWidgetTypes[type];
        if (!info) return $();

        var $card = $('<div class="fdp-widget-card' + (isChild ? ' fdp-child-card' : '') + '" data-type="' + type + '"></div>');

        var displayLabel = info.label;
        if (type === 'accordion' && data.title) {
            displayLabel = info.label + ': ' + data.title;
        }

        // Card header
        $card.append(
            '<div class="fdp-widget-card-header" style="cursor: pointer;" title="Click to toggle">' +
            '<span class="fdp-widget-drag" title="Drag to reorder">&#x2807;</span>' +
            '<span class="fdp-widget-toggle-icon" style="transition: transform 0.2s; font-size: 10px; margin: 0 5px; color: #555; transform: rotate(-90deg);">&#9660;</span>' +
            '<span class="fdp-widget-badge" style="background:' + info.color + ';">' + info.icon + '&nbsp;<span class="fdp-wb-text">' + fdpEscHtml(displayLabel) + '</span></span>' +
            '<button type="button" class="fdp-widget-duplicate" style="margin-left: auto; margin-right: 5px; color: #0073aa; border: 1px solid #0073aa; background: transparent; padding: 2px 5px; border-radius: 3px; cursor: pointer;">Duplicate</button>' +
            '<button type="button" class="fdp-widget-remove">&times; Remove</button>' +
            '</div>'
        );

        // Card body
        var $body = $('<div class="fdp-widget-card-body" style="display: none;"></div>');

        switch (type) {
            case 'accordion':
                $body.append(
                    '<div class="fdp-wfield">' +
                    '<label>Accordion Title</label>' +
                    '<input type="text" class="fdp-wf-title large-text" value="' + fdpEscAttr(data.title || '') + '" placeholder="e.g. Step 1: Getting the parking pass">' +
                    '</div>' +
                    '<div class="fdp-wfield">' +
                    '<label>Step Video URL <span class="fdp-hint">(optional — paste a YouTube link, opens in popup)</span></label>' +
                    '<input type="text" class="fdp-wf-video-url large-text" value="' + fdpEscAttr(data.video_url || '') + '" placeholder="https://youtu.be/...">' +
                    '</div>' +
                    '<div class="fdp-wfield fdp-children-field">' +
                    '<label>Child Widgets <span class="fdp-hint">(instruction rows, videos, maps, text blocks)</span></label>' +
                    '<div class="fdp-child-list"></div>' +
                    '<button type="button" class="button fdp-add-child-widget" style="margin-top:8px;">&#43; Add Child Widget</button>' +
                    '</div>'
                );
                // Render existing children
                if (data.children && data.children.length) {
                    var $cl = $body.find('.fdp-child-list');
                    data.children.forEach(function (child) {
                        $cl.append(fdpCreateCard(child.type, child, true));
                    });
                    fdpInitSortable($cl);
                }
                break;

            case 'instruction_row':
                $body.append(
                    '<div class="fdp-wfield">' +
                    '<label>Instruction Text <span class="fdp-hint">(HTML &amp; shortcodes OK)</span></label>' +
                    '<textarea class="fdp-wf-text large-text" rows="3" placeholder="Describe this step...">' + fdpEscHtml(data.text || '') + '</textarea>' +
                    '<div class="fdp-insert-field-wrap">' +
                    '<button type="button" class="button button-small fdp-insert-field-btn">&#x2295; Insert Dynamic Field</button>' +
                    '<div class="fdp-field-chips" style="display:none;"></div>' +
                    '</div>' +
                    '</div>' +
                    '<div class="fdp-wfield">' +
                    '<label>Google Maps URL <span class="fdp-hint">(optional — shows a map link below the text)</span></label>' +
                    '<input type="text" class="fdp-wf-map-url large-text" value="' + fdpEscAttr(data.map_url || '') + '" placeholder="https://maps.app.goo.gl/...">' +
                    '</div>' +
                    '<div class="fdp-wfield">' +
                    '<label>YouTube Video URL <span class="fdp-hint">(optional — shows a popup video link below the text)</span></label>' +
                    '<input type="text" class="fdp-wf-video-url large-text" value="' + fdpEscAttr(data.video_url || '') + '" placeholder="https://youtu.be/...">' +
                    '</div>' +
                    '<div class="fdp-wfield">' +
                    '<label>Image URL <span class="fdp-hint">(optional — shown on the right side)</span></label>' +
                    '<input type="text" class="fdp-wf-image-url large-text" value="' + fdpEscAttr(data.image_url || '') + '" placeholder="https://example.com/image.jpg">' +
                    '</div>'
                );
                break;

            case 'youtube_video':
                $body.append(
                    '<div class="fdp-wfield">' +
                    '<label>YouTube Video URL</label>' +
                    '<input type="text" class="fdp-wf-video-url large-text" value="' + fdpEscAttr(data.video_url || '') + '" placeholder="https://youtu.be/... or https://www.youtube.com/watch?v=...">' +
                    '</div>'
                );
                break;

            case 'google_map':
                $body.append(
                    '<div class="fdp-wfield">' +
                    '<label>Google Maps URL</label>' +
                    '<input type="text" class="fdp-wf-map-url large-text" value="' + fdpEscAttr(data.map_url || '') + '" placeholder="https://maps.app.goo.gl/...">' +
                    '</div>' +
                    '<div class="fdp-wfield">' +
                    '<label>Link Label <span class="fdp-hint">(optional, default: "View on Google Maps")</span></label>' +
                    '<input type="text" class="fdp-wf-map-label large-text" value="' + fdpEscAttr(data.label || '') + '" placeholder="View on Google Maps">' +
                    '</div>'
                );
                break;

            case 'rich_text':
                $body.append(
                    '<div class="fdp-wfield">' +
                    '<label>Text / HTML <span class="fdp-hint">(shortcodes like [fluent_dynamic field="..."] are supported)</span></label>' +
                    '<textarea class="fdp-wf-text large-text" rows="4" placeholder="Enter your text here...">' + fdpEscHtml(data.text || '') + '</textarea>' +
                    '<div class="fdp-insert-field-wrap">' +
                    '<button type="button" class="button button-small fdp-insert-field-btn">&#x2295; Insert Dynamic Field</button>' +
                    '<div class="fdp-field-chips" style="display:none;"></div>' +
                    '</div>' +
                    '</div>'
                );
                break;

            case 'divider':
                $body.append('<p class="fdp-divider-note">Renders a horizontal &lt;hr&gt; separator line — no configuration needed.</p>');
                break;

            case 'notice':
                var nType = data.notice_type || 'info';
                $body.append(
                    '<div class="fdp-wfield">' +
                    '<label>Notice Type</label>' +
                    '<select class="fdp-wf-notice-type large-text">' +
                    '<option value="info"' + (nType === 'info' ? ' selected' : '') + '>Info (Blue)</option>' +
                    '<option value="success"' + (nType === 'success' ? ' selected' : '') + '>Success (Green)</option>' +
                    '<option value="warning"' + (nType === 'warning' ? ' selected' : '') + '>Warning (Yellow)</option>' +
                    '<option value="error"' + (nType === 'error' ? ' selected' : '') + '>Error (Red)</option>' +
                    '</select>' +
                    '</div>' +
                    '<div class="fdp-wfield">' +
                    '<label>Notice Title (Optional)</label>' +
                    '<input type="text" class="fdp-wf-title large-text" value="' + fdpEscAttr(data.title || '') + '" placeholder="Important Update">' +
                    '</div>' +
                    '<div class="fdp-wfield">' +
                    '<label>Notice Text <span class="fdp-hint">(shortcodes supported)</span></label>' +
                    '<textarea class="fdp-wf-text large-text" rows="3" placeholder="Enter notice details...">' + fdpEscHtml(data.text || '') + '</textarea>' +
                    '</div>'
                );
                break;

            case 'popup':
                var pTrigger = data.trigger || 'page_load';
                $body.append(
                    '<div class="fdp-wfield">' +
                    '<label>Trigger Action</label>' +
                    '<select class="fdp-wf-trigger large-text">' +
                    '<option value="page_load"' + (pTrigger === 'page_load' ? ' selected' : '') + '>On Page Load</option>' +
                    '<option value="button_click"' + (pTrigger === 'button_click' ? ' selected' : '') + '>On Button Click [fdp_popup_button]</option>' +
                    '<option value="exit_intent"' + (pTrigger === 'exit_intent' ? ' selected' : '') + '>On Exit Intent (Mouse leaves window)</option>' +
                    '</select>' +
                    '</div>' +
                    '<div class="fdp-wfield">' +
                    '<label>Delay (Seconds) <span class="fdp-hint">(for Page Load trigger)</span></label>' +
                    '<input type="number" class="fdp-wf-delay large-text" value="' + fdpEscAttr(data.delay || '0') + '" min="0" step="1">' +
                    '</div>' +
                    '<div class="fdp-wfield">' +
                    '<label>Popup Content <span class="fdp-hint">(HTML &amp; shortcodes supported)</span></label>' +
                    '<textarea class="fdp-wf-text large-text" rows="5" placeholder="Enter popup content...">' + fdpEscHtml(data.text || '') + '</textarea>' +
                    '<div class="fdp-insert-field-wrap">' +
                    '<button type="button" class="button button-small fdp-insert-field-btn">&#x2295; Insert Dynamic Field</button>' +
                    '<div class="fdp-field-chips" style="display:none;"></div>' +
                    '</div>' +
                    '</div>'
                );
                break;
        }

        $card.append($body);
        return $card;
    }

    // ── Init jQuery UI Sortable on a widget list ──────────────────
    function fdpInitSortable($list) {
        if (!$.fn.sortable) return;
        if ($list.data('ui-sortable')) return; // already initialized
        $list.sortable({
            handle: '.fdp-widget-drag',
            items: '> .fdp-widget-card',
            placeholder: 'fdp-widget-placeholder',
            forcePlaceholderSize: true,
            tolerance: 'pointer'
        });
    }

    // ── Load widget cards into a pane from its JSON store ─────────
    function fdpLoadWidgetPane($pane) {
        var json = $pane.find('.fdp-widgets-json-store').val();
        if (!json || json === '[]') return;
        var widgets = [];
        try { widgets = JSON.parse(json); } catch (e) { console.error("FDP JSON parse error:", e, json); return; }
        if (!Array.isArray(widgets) || !widgets.length) return;

        var $list = $pane.find('.fdp-widget-list');
        widgets.forEach(function (w) {
            $list.append(fdpCreateCard(w.type, w, false));
        });
        fdpInitSortable($list);
    }

    // ── Open the palette modal ────────────────────────────────────
    function fdpOpenPalette($targetList, isChild) {
        fdpPaletteTarget = $targetList;
        fdpPaletteIsChild = isChild;

        var types = isChild ? fdpChildTypes : fdpRootTypes;
        var $modal = $('#fdp-widget-palette');
        var $grid = $modal.find('.fdp-palette-grid');

        $grid.empty();
        types.forEach(function (type) {
            var info = fdpWidgetTypes[type];
            $grid.append(
                '<div class="fdp-palette-card" data-type="' + type + '" style="border-top:3px solid ' + info.color + ';">' +
                '<div class="fdp-palette-icon">' + info.iconText + '</div>' +
                '<div class="fdp-palette-label">' + info.label + '</div>' +
                '<div class="fdp-palette-desc">' + info.desc + '</div>' +
                '</div>'
            );
        });

        $modal.css('display', 'flex');
    }

    function fdpClosePalette() {
        $('#fdp-widget-palette').hide();
    }

    // ── Serialize all widget panes on form submit ─────────────────
    function fdpSerializeAll() {
        $('.fdp-section-item').not('#fdp_section_template .fdp-section-item').each(function () {
            var $section = $(this);
            var $widgetPane = $section.find('.fdp-editor-pane.widget');
            if (!$widgetPane.length) return;

            var activeTab = $section.find('.fdp-active-tab-input').val();
            if (activeTab !== 'widget') return;

            var widgets = fdpCollectFromList($widgetPane.find('.fdp-widget-list'));
            var json = JSON.stringify(widgets);
            var html = fdpWidgetsToHtml(widgets);

            // Save JSON for reloading the widget builder on next edit
            $section.find('.fdp-widgets-json-store').val(json);

            // ALWAYS set the textarea value directly first — this is what the form actually submits.
            // This works regardless of whether CodeMirror was initialized.
            var $textarea = $section.find('.fdp-editor-textarea');
            $textarea.val(html);

            // Optionally sync to CodeMirror if it has been initialized
            var cmId = $textarea.attr('id');
            if (cmInstances[cmId]) {
                try {
                    cmInstances[cmId].setValue(html);
                    cmInstances[cmId].save();
                } catch (e) { }
            }
        });
    }

    // ── Events ────────────────────────────────────────────────────

    // Open root widget palette
    $(document).on('click', '.fdp-open-palette', function () {
        var $pane = $(this).closest('.fdp-editor-pane.widget');
        fdpOpenPalette($pane.find('.fdp-widget-list'), false);
    });

    // Open child widget palette (inside accordion)
    $(document).on('click', '.fdp-add-child-widget', function () {
        var $childList = $(this).closest('.fdp-children-field').find('.fdp-child-list');
        fdpOpenPalette($childList, true);
    });

    // Pick widget from palette
    $(document).on('click', '.fdp-palette-card', function () {
        if (!fdpPaletteTarget) return;
        var type = $(this).attr('data-type');
        var $card = fdpCreateCard(type, {}, fdpPaletteIsChild);
        fdpPaletteTarget.append($card);
        fdpInitSortable(fdpPaletteTarget);
        fdpClosePalette();
    });

    // Close palette
    $(document).on('click', '#fdp-palette-close', fdpClosePalette);
    $(document).on('click', '#fdp-widget-palette', function (e) {
        if ($(e.target).is('#fdp-widget-palette')) fdpClosePalette();
    });

    // Remove a widget card
    $(document).on('click', '.fdp-widget-remove', function () {
        if (confirm('Remove this widget?')) {
            $(this).closest('.fdp-widget-card').remove();
        }
    });

    // Duplicate a widget card
    $(document).on('click', '.fdp-widget-duplicate', function (e) {
        e.stopPropagation(); // prevent toggle
        var $card = $(this).closest('.fdp-widget-card');

        // Wrap the card in a temp div to collect its data
        var $temp = $('<div></div>').append($card.clone());
        var wData = fdpCollectFromList($temp);

        if (wData && wData.length > 0) {
            var data = wData[0];

            // Append (duplicate) to title/text if applicable
            if (data.title) data.title += ' (duplicate)';
            if (data.text) data.text += ' (duplicate)';

            var isChild = $card.hasClass('fdp-child-card');
            var $newCard = fdpCreateCard(data.type, data, isChild);

            $card.after($newCard);
        }
    });

    // Insert dynamic field chip button
    $(document).on('click', '.fdp-insert-field-btn', function (e) {
        e.stopPropagation();
        var $wrap = $(this).closest('.fdp-insert-field-wrap');
        var $chips = $wrap.find('.fdp-field-chips');
        var $textarea = $wrap.closest('.fdp-wfield').find('.fdp-wf-text');

        // Capture cursor position before the button click blurs the textarea
        fdpLastTextarea = $textarea[0];
        fdpLastCursorPos = fdpLastTextarea ? (fdpLastTextarea.selectionStart || 0) : 0;

        if ($chips.is(':visible')) { $chips.hide(); return; }

        $chips.empty();
        if (!cachedFields || cachedFields.length === 0) {
            $chips.append('<em style="color:#888;padding:4px 2px;display:block;font-size:12px;">Select a form first (in the Fluent Form Mapping box above).</em>');
        } else {
            cachedFields.forEach(function (field) {
                var sc = '[fluent_dynamic field="' + field.name + '"]';
                $chips.append('<span class="fdp-field-chip" data-sc="' + fdpEscAttr(sc) + '">' + fdpEscHtml(field.label) + '</span>');
            });
        }
        $chips.show();
    });

    // Insert shortcode chip into textarea
    $(document).on('click', '.fdp-field-chip', function () {
        var sc = $(this).attr('data-sc');
        var ta = fdpLastTextarea;
        if (ta) {
            var pos = typeof fdpLastCursorPos === 'number' ? fdpLastCursorPos : ta.value.length;
            ta.value = ta.value.slice(0, pos) + sc + ta.value.slice(pos);
            var newPos = pos + sc.length;
            ta.selectionStart = ta.selectionEnd = newPos;
            fdpLastCursorPos = newPos;
            ta.focus();
        }
        $(this).closest('.fdp-field-chips').hide();
    });

    // Close chip dropdown when clicking outside
    $(document).on('click', function (e) {
        if (!$(e.target).closest('.fdp-insert-field-wrap').length) {
            $('.fdp-field-chips').hide();
        }
    });

    // Track cursor position whenever a widget text area loses focus
    $(document).on('blur', '.fdp-wf-text', function () {
        fdpLastTextarea = this;
        fdpLastCursorPos = this.selectionStart || 0;
    });

    // Tab switching — keep active_tab hidden input in sync,
    // and auto-generate HTML into code editor when switching to Code view
    $(document).on('click', '.fdp-tab-btn', function () {
        var target = $(this).attr('data-target');
        var $section = $(this).closest('.fdp-section-item');
        var $input = $section.find('.fdp-active-tab-input');

        if (target === 'widget' || target === 'code') {
            $input.val(target);
        }

        // Switching to Code Builder → auto-fill editor with widget HTML (if widgets exist)
        if (target === 'code') {
            var $widgetPane = $section.find('.fdp-editor-pane.widget');
            if ($widgetPane.length) {
                var ws = fdpCollectFromList($widgetPane.find('.fdp-widget-list'));
                if (ws.length > 0) {
                    var html = fdpWidgetsToHtml(ws);
                    var $ta = $section.find('.fdp-editor-textarea');
                    // Always set textarea directly (CM may not be initialized yet)
                    $ta.val(html);
                    var cmId = $ta.attr('id');
                    if (cmInstances[cmId]) {
                        try { cmInstances[cmId].setValue(html); } catch (e) { }
                    }
                }
            }
        }
    });

    // Initialize widget panes for all existing sections on page load
    $('.fdp-section-item').not('#fdp_section_template .fdp-section-item').each(function () {
        var $pane = $(this).find('.fdp-editor-pane.widget');
        if ($pane.length) {
            fdpLoadWidgetPane($pane);
            fdpInitSortable($pane.find('.fdp-widget-list'));
        }
    });

    // Update section title label dynamically when the title input changes
    $(document).on('input', '.fdp-section-title-input', function () {
        var val = $(this).val().trim();
        var label = val ? val : 'Section';
        $(this).closest('.fdp-section-item').find('.fdp-section-title-label').text(label);
    });

    // Toggle widget card body
    $(document).on('click', '.fdp-widget-card-header', function (e) {
        if ($(e.target).closest('.fdp-widget-remove, .fdp-widget-duplicate, .fdp-widget-drag').length) return;
        var $body = $(this).siblings('.fdp-widget-card-body');
        var $icon = $(this).find('.fdp-widget-toggle-icon');
        $body.slideToggle(200, function () {
            if ($body.is(':visible')) {
                $icon.css('transform', 'rotate(0deg)');
            } else {
                $icon.css('transform', 'rotate(-90deg)');
            }
        });
    });

    // Update accordion widget title label dynamically
    $(document).on('input', '.fdp-wf-title', function () {
        var val = $(this).val().trim();
        var label = val ? 'Accordion: ' + val : 'Accordion';
        $(this).closest('.fdp-widget-card').find('.fdp-wb-text').text(label);
    });

});
