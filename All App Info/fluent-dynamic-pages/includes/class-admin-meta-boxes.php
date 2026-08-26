<?php
if (!defined('ABSPATH')) {
    exit;
}

class FDP_Admin_Meta_Boxes
{

    public function __construct()
    {
        add_action('add_meta_boxes', array($this, 'add_meta_boxes'));
        add_action('save_post', array($this, 'save_meta_boxes'));
        add_action('admin_enqueue_scripts', array($this, 'enqueue_admin_scripts'));
        add_action('wp_ajax_fdp_get_form_fields', array($this, 'ajax_get_form_fields'));
    }

    public function add_meta_boxes()
    {
        add_meta_box(
            'fdp_form_mapping_meta',
            __('Fluent Form Mapping', 'fluent-dynamic-pages'),
            array($this, 'render_form_mapping_meta_box'),
            'fluent_dynamic_page',
            'normal',
            'high'
        );

        add_meta_box(
            'fdp_custom_heading_meta',
            __('Custom Page Heading', 'fluent-dynamic-pages'),
            array($this, 'render_custom_heading_meta_box'),
            'fluent_dynamic_page',
            'normal',
            'high'
        );

        add_meta_box(
            'fdp_static_content_meta',
            __('Global Static Content', 'fluent-dynamic-pages'),
            array($this, 'render_static_content_meta_box'),
            'fluent_dynamic_page',
            'normal',
            'high'
        );



        add_meta_box(
            'fdp_dynamic_sections_meta',
            __('Dynamic Sections Builder', 'fluent-dynamic-pages'),
            array($this, 'render_dynamic_sections_meta_box'),
            'fluent_dynamic_page',
            'advanced',
            'high'
        );

        add_meta_box(
            'fdp_instructions_meta_box',
            __('How to Use This Plugin', 'fluent-dynamic-pages'),
            array($this, 'render_instructions_meta_box'),
            'fluent_dynamic_page',
            'side',
            'high'
        );
    }

    public function enqueue_admin_scripts($hook)
    {
        if (!in_array($hook, array('post.php', 'post-new.php'), true)) {
            return;
        }
        global $post;
        if (!$post || 'fluent_dynamic_page' !== $post->post_type) {
            return;
        }

        $cm_settings = wp_enqueue_code_editor(array('type' => 'text/html'));
        wp_enqueue_script('wp-theme-plugin-editor');
        wp_enqueue_style('wp-codemirror');

        $js_ver = file_exists(FF_DYNAMIC_PAGES_DIR . 'assets/admin.js') ? filemtime(FF_DYNAMIC_PAGES_DIR . 'assets/admin.js') : FF_DYNAMIC_PAGES_VERSION;
        wp_enqueue_script('fdp-admin-js', FF_DYNAMIC_PAGES_URL . 'assets/admin.js', array('jquery', 'jquery-ui-sortable'), $js_ver, true);
        wp_localize_script('fdp-admin-js', 'fdp_ajax', array(
            'ajax_url' => admin_url('admin-ajax.php'),
            'nonce' => wp_create_nonce('fdp_admin_nonce'),
            'cm_settings' => $cm_settings
        ));
    }

    public function render_instructions_meta_box($post)
    {
        echo '<div style="font-size: 13px; line-height: 1.5;">';
        echo '<h4 style="margin-top: 0;">1. Map the Form</h4>';
        echo '<p>Select the Fluent Form from the "Fluent Form Mapping" dropdown below.</p>';

        echo '<h4>2. Build Your Content</h4>';
        echo '<p>Click <strong>+ Add New Section</strong> to create a content block.</p>';
        echo '<p>You can use dynamic shortcodes to inject the user\'s submitted data. For example: <br><code>[fluent_dynamic field="door_code"]</code></p>';
        echo '<p>To calculate dynamic numbers (like adding a room number to a base code), use the math_add attribute: <br><code>Emergency Bedroom Door Code: [fluent_dynamic field="room" math_add="270380"]</code></p>';
        echo '<p>To add a popup video link inside any text, use: <br><code>[fdp_video url="YOUR_YOUTUBE_URL"]Click to watch![/fdp_video]</code></p>';

        echo '<h4>3. Add Logic Conditions</h4>';
        echo '<p>If you only want a section to show based on the user\'s form entry, use the <strong>Display Conditions</strong> area under each section.</p>';

        echo '<h4>4. Email the Secure Link</h4>';
        echo '<p>To automatically send the generated webpage back to the user who filled out the form, paste this exact code into your Fluent Forms Email Notification body:</p>';
        echo '<p><code style="background: #f0f0f1; padding: 4px; display: block; text-align: center; font-size: 14px;">{dynamic_page_link}</code></p>';

        echo '<p style="margin-top: 15px; border-top: 1px solid #ddd; padding-top: 10px;"><em>Note: The generated URLs contain a highly secure 32-character hash. If a visitor opens the link without the hash, none of the dynamic data or restricted sections will be shown.</em></p>';
        echo '</div>';
    }

    public function render_form_mapping_meta_box($post)
    {
        wp_nonce_field('fdp_save_meta_box_data', 'fdp_meta_box_nonce');

        $mapped_form_id = get_post_meta($post->ID, '_fdp_mapped_form_id', true);

        global $wpdb;
        $forms_table = $wpdb->prefix . 'fluentform_forms';
        $forms = array();

        if ($wpdb->get_var("SHOW TABLES LIKE '$forms_table'") === $forms_table) {
            $forms = $wpdb->get_results("SELECT id, title FROM {$forms_table} ORDER BY id DESC");
        }

        echo '<p><label for="fdp_mapped_form_id">';
        _e('Select the Fluent Form to map to this webpage:', 'fluent-dynamic-pages');
        echo '</label></p>';

        echo '<select id="fdp_mapped_form_id" name="fdp_mapped_form_id" style="width: 100%; max-width: 400px;">';
        echo '<option value="">' . __('-- Select a Form --', 'fluent-dynamic-pages') . '</option>';
        if (!empty($forms)) {
            foreach ($forms as $form) {
                $selected = selected($mapped_form_id, $form->id, false);
                echo '<option value="' . esc_attr($form->id) . '" ' . $selected . '>' . esc_html($form->title) . ' (ID: ' . esc_html($form->id) . ')</option>';
            }
        } else {
            echo '<option value="" disabled>' . __('No Fluent Forms found. Is Fluent Forms installed?', 'fluent-dynamic-pages') . '</option>';
        }
        echo '</select>';

        echo '<div id="fdp_form_fields_container" style="margin-top: 15px; padding: 10px; background: #f9f9f9; border: 1px solid #ddd;">';
        echo '<p><strong>' . __('Available Form Fields (Name Attributes)', 'fluent-dynamic-pages') . '</strong></p>';
        echo '<p>' . __('Select a form above to view available fields. You can use these in the editor like <code>[fluent_dynamic field="name_attribute"]</code>.', 'fluent-dynamic-pages') . '</p>';
        echo '<p>' . __('Conditional logic: <code>[fluent_if field="name_attribute" condition="equals" value="123"]...[/fluent_if]</code>. Valid conditions: equals, not_equals, greater_than, less_than, contains.', 'fluent-dynamic-pages') . '</p>';
        echo '<ul id="fdp_form_fields_list" style="margin-top: 10px; list-style-type: disc; padding-left: 20px;"></ul>';
        echo '</div>';
    }

    public function render_custom_heading_meta_box($post)
    {
        $heading_settings = get_post_meta($post->ID, '_fdp_heading_settings', true);
        if (!is_array($heading_settings)) {
            $heading_settings = array();
        }

        $text = isset($heading_settings['text']) ? $heading_settings['text'] : '';
        $tag = isset($heading_settings['tag']) ? $heading_settings['tag'] : 'h1';
        $color = isset($heading_settings['color']) ? $heading_settings['color'] : '';
        $align = isset($heading_settings['align']) ? $heading_settings['align'] : 'left';
        $hide_title = isset($heading_settings['hide_title']) ? $heading_settings['hide_title'] : '';

        echo '<table class="form-table">';

        echo '<tr>';
        echo '<th scope="row"><label for="fdp_heading_text">' . __('Heading Text', 'fluent-dynamic-pages') . '</label></th>';
        echo '<td><input type="text" id="fdp_heading_text" name="fdp_heading_settings[text]" value="' . esc_attr($text) . '" class="large-text" placeholder="' . __('Enter custom heading... (leave empty to disable)', 'fluent-dynamic-pages') . '" /><br><span class="description">' . __('Shortcodes are supported.', 'fluent-dynamic-pages') . '</span></td>';
        echo '</tr>';

        echo '<tr>';
        echo '<th scope="row"><label for="fdp_heading_tag">' . __('HTML Tag', 'fluent-dynamic-pages') . '</label></th>';
        echo '<td>';
        echo '<select id="fdp_heading_tag" name="fdp_heading_settings[tag]">';
        foreach (array('h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'div') as $t) {
            echo '<option value="' . $t . '" ' . selected($t, $tag, false) . '>' . strtoupper($t) . '</option>';
        }
        echo '</select>';
        echo '</td>';
        echo '</tr>';

        echo '<tr>';
        echo '<th scope="row"><label for="fdp_heading_color">' . __('Text Color', 'fluent-dynamic-pages') . '</label></th>';
        echo '<td><input type="text" id="fdp_heading_color" name="fdp_heading_settings[color]" value="' . esc_attr($color) . '" placeholder="#000000" /></td>';
        echo '</tr>';

        echo '<tr>';
        echo '<th scope="row"><label for="fdp_heading_align">' . __('Text Alignment', 'fluent-dynamic-pages') . '</label></th>';
        echo '<td>';
        echo '<select id="fdp_heading_align" name="fdp_heading_settings[align]">';
        echo '<option value="left" ' . selected('left', $align, false) . '>' . __('Left', 'fluent-dynamic-pages') . '</option>';
        echo '<option value="center" ' . selected('center', $align, false) . '>' . __('Center', 'fluent-dynamic-pages') . '</option>';
        echo '<option value="right" ' . selected('right', $align, false) . '>' . __('Right', 'fluent-dynamic-pages') . '</option>';
        echo '</select>';
        echo '</td>';
        echo '</tr>';

        echo '<tr>';
        echo '<th scope="row"><label for="fdp_heading_hide_title">' . __('Hide Theme Title', 'fluent-dynamic-pages') . '</label></th>';
        echo '<td><input type="checkbox" id="fdp_heading_hide_title" name="fdp_heading_settings[hide_title]" value="1" ' . checked(1, $hide_title, false) . ' /> ' . __('Try to hide the default theme page title.', 'fluent-dynamic-pages') . '</td>';
        echo '</tr>';

        echo '</table>';
    }

    public function render_static_content_meta_box($post)
    {
        $static_content = get_post_meta($post->ID, '_fdp_static_content', true);
        echo '<p>' . __('This content will always appear at the top of the page, regardless of conditional logic. Shortcodes are supported.', 'fluent-dynamic-pages') . '</p>';
        wp_editor($static_content, 'fdp_static_content', array(
            'textarea_name' => 'fdp_static_content',
            'textarea_rows' => 8,
            'media_buttons' => true,
        ));
    }


    public function render_dynamic_sections_meta_box($post)
    {
        $sections = get_post_meta($post->ID, '_fdp_dynamic_sections', true);
        if (!is_array($sections)) {
            $sections = array();
        }

        echo '<div id="fdp_sections_wrapper">';

        echo '<div id="fdp_section_template" style="display:none;" class="fdp-section-item">';
        echo $this->get_section_html(array('title' => '', 'content' => '', 'condition_match' => 'all', 'conditions' => array()), '{INDEX}');
        echo '</div>';

        echo '<div id="fdp_sections_list">';
        if (!empty($sections)) {
            foreach ($sections as $index => $section) {
                echo '<div class="fdp-section-item" data-index="' . esc_attr($index) . '">';
                echo $this->get_section_html($section, $index);
                echo '</div>';
            }
        }
        echo '</div>';

        echo '<p><button type="button" class="button button-primary" id="fdp_add_section">' . __('+ Add New Section', 'fluent-dynamic-pages') . '</button></p>';
        echo '</div>';

        echo '<style>
            .fdp-section-item { border: 1px solid #ccd0d4; padding: 15px; margin-bottom: 15px; background: #fff; box-shadow: 0 1px 1px rgba(0,0,0,.04); }
            .fdp-section-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 10px; cursor: move; }
            .fdp-section-header h4 { margin: 0; }
            .fdp-condition-row { display: flex; gap: 10px; margin-bottom: 5px; align-items: center; }
            .fdp-remove-section { color: #b32d2e; text-decoration: none; }
            .fdp-remove-condition { color: #b32d2e; cursor: pointer; font-size: 20px; line-height: 1; }
            .fdp-editor-tabs { border-bottom: 1px solid #ccc; margin-bottom: 0; }
            .fdp-tab-btn { background: #f1f1f1; border: 1px solid #ccc; border-bottom: none; padding: 8px 15px; cursor: pointer; margin-right: 5px; font-weight: bold; border-radius: 4px 4px 0 0; outline: none; }
            .fdp-tab-btn.active { background: #fff; border-bottom-color: #fff; position: relative; top: 1px; color: #2271b1; }
            .fdp-editor-pane { border: 1px solid #ccc; width: 100%; box-sizing: border-box; resize: vertical; height: 400px; min-height: 200px; }
            .fdp-editor-pane.preview { display: none; padding: 0; background: #fafafa; border-top: none; overflow-y: auto; overflow-x: hidden; }
            .fdp-editor-pane.code { border-top: none; overflow: hidden; }
            .CodeMirror { border: none !important; height: 100% !important; }
            /* ── Widget Builder Pane ── */
            .fdp-editor-pane.widget { height: auto; min-height: 120px; padding: 14px; background: #f7f9fb; border-top: none; resize: none; overflow: visible; }
            .fdp-widget-list { min-height: 50px; }
            .fdp-widget-toolbar { margin-top: 10px; }
            /* Widget Cards */
            .fdp-widget-card { background: #fff; border: 1px solid #dde3ec; border-radius: 7px; margin-bottom: 10px; box-shadow: 0 1px 4px rgba(0,0,0,0.06); }
            .fdp-child-card { background: #f8fafc; border-color: #c8d4e3; }
            .fdp-widget-card-header { display: flex; align-items: center; gap: 10px; padding: 9px 14px; border-radius: 7px 7px 0 0; background: #f1f5f9; border-bottom: 1px solid #dde3ec; }
            .fdp-widget-drag { cursor: grab; color: #94a3b8; font-size: 18px; line-height: 1; user-select: none; flex-shrink: 0; }
            .fdp-widget-badge { font-size: 11px; font-weight: 700; color: #fff; padding: 3px 11px; border-radius: 20px; letter-spacing: .3px; }
            .fdp-widget-remove { background: none; border: none; color: #dc2626; cursor: pointer; font-size: 12px; font-weight: 600; padding: 3px 8px; margin-left: auto; border-radius: 4px; transition: background .15s; }
            .fdp-widget-remove:hover { background: #fee2e2; }
            .fdp-widget-card-body { padding: 14px 16px; }
            /* Widget Fields */
            .fdp-wfield { margin-bottom: 12px; }
            .fdp-wfield:last-child { margin-bottom: 0; }
            .fdp-wfield > label { display: block; font-weight: 600; font-size: 11px; text-transform: uppercase; letter-spacing: .5px; color: #475569; margin-bottom: 5px; }
            .fdp-hint { font-weight: 400; text-transform: none; letter-spacing: 0; color: #94a3b8; font-size: 11px; }
            .fdp-wfield input.large-text, .fdp-wfield textarea.large-text { width: 100%; box-sizing: border-box; }
            .fdp-divider-note { color: #94a3b8; font-style: italic; font-size: 13px; margin: 0; }
            /* Child list */
            .fdp-child-list { min-height: 44px; border: 2px dashed #c8d4e3; border-radius: 5px; padding: 8px; background: #f0f5fb; }
            .fdp-child-list > .fdp-widget-card { margin-bottom: 8px; }
            .fdp-child-list > .fdp-widget-card:last-child { margin-bottom: 0; }
            /* Insert dynamic field */
            .fdp-insert-field-wrap { position: relative; margin-top: 6px; }
            .fdp-field-chips { position: absolute; left: 0; top: 100%; margin-top: 4px; background: #fff; border: 1px solid #dde3ec; border-radius: 7px; padding: 8px 10px; z-index: 9999; display: flex; flex-wrap: wrap; gap: 5px; max-width: 420px; box-shadow: 0 6px 18px rgba(0,0,0,.12); }
            .fdp-field-chip { background: #e0f2fe; color: #0369a1; border-radius: 4px; padding: 3px 9px; font-size: 12px; cursor: pointer; border: 1px solid #bae6fd; white-space: nowrap; }
            .fdp-field-chip:hover { background: #bae6fd; }
            /* Sortable placeholder */
            .fdp-widget-placeholder { height: 52px; background: #dbeafe; border: 2px dashed #93c5fd; border-radius: 6px; margin-bottom: 10px; }
            /* Palette Modal */
            #fdp-widget-palette { position: fixed; top: 0; left: 0; width: 100%; height: 100%; z-index: 999999; display: none; justify-content: center; align-items: center; background: rgba(10,20,40,.62); }
            .fdp-palette-box { background: #fff; border-radius: 12px; padding: 28px 28px 24px; max-width: 680px; width: 92%; max-height: 82vh; overflow-y: auto; position: relative; box-shadow: 0 24px 64px rgba(0,0,0,.35); }
            .fdp-palette-title { margin: 0 0 18px; font-size: 1.1rem; font-weight: 700; color: #1e293b; }
            .fdp-palette-close { position: absolute; top: 14px; right: 16px; background: none; border: none; font-size: 22px; line-height: 1; cursor: pointer; color: #64748b; padding: 2px 6px; border-radius: 4px; }
            .fdp-palette-close:hover { background: #f1f5f9; color: #1e293b; }
            .fdp-palette-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(170px, 1fr)); gap: 12px; }
            .fdp-palette-card { border: 1px solid #e2e8f0; border-radius: 8px; padding: 16px 12px 14px; cursor: pointer; text-align: center; background: #fff; transition: box-shadow .2s, transform .15s; }
            .fdp-palette-card:hover { box-shadow: 0 6px 20px rgba(0,0,0,.14); transform: translateY(-2px); }
            .fdp-palette-icon { font-size: 2rem; line-height: 1; margin-bottom: 8px; }
            .fdp-palette-label { font-weight: 700; font-size: 13px; margin-bottom: 4px; color: #1e293b; }
            .fdp-palette-desc { font-size: 11px; color: #64748b; line-height: 1.45; }
        </style>';

        /* ── Widget Palette Modal (one shared instance) ── */
        echo '<div id="fdp-widget-palette">';
        echo '  <div class="fdp-palette-box">';
        echo '    <button type="button" id="fdp-palette-close" class="fdp-palette-close" title="Close">&times;</button>';
        echo '    <h3 class="fdp-palette-title">Choose a Widget</h3>';
        echo '    <div class="fdp-palette-grid"></div>';
        echo '  </div>';
        echo '</div>';
    }

    private function get_section_html($section, $index)
    {
        ob_start();
        ?>
        <div class="fdp-section-header">
            <h4 class="fdp-section-toggle" title="<?php _e('Click to toggle', 'fluent-dynamic-pages'); ?>"
                style="cursor: pointer; display: flex; align-items: center; gap: 8px;">
                <span class="fdp-toggle-icon"
                    style="transition: transform 0.2s; font-size: 12px; color: #555; transform: rotate(-90deg);">&#9660;</span>
                <span
                    class="fdp-section-title-label"><?php echo esc_html(!empty($section['title']) ? $section['title'] : __('Section', 'fluent-dynamic-pages')); ?></span>
            </h4>
            <div style="display: flex; gap: 15px; align-items: center; margin-left: auto;">
                <a href="#" class="fdp-duplicate-section"
                    style="color: #0073aa; text-decoration: none;"><?php _e('Duplicate', 'fluent-dynamic-pages'); ?></a>
                <a href="#" class="fdp-remove-section"
                    style="color: #a00; text-decoration: none;"><?php _e('Remove', 'fluent-dynamic-pages'); ?></a>
            </div>
        </div>
        <div class="fdp-section-body" style="display: none;">

            <p>
                <label><strong><?php _e('Section Title (Optional)', 'fluent-dynamic-pages'); ?></strong></label><br>
                <input type="text" class="fdp-section-title-input" name="fdp_sections[<?php echo $index; ?>][title]"
                    value="<?php echo esc_attr(isset($section['title']) ? $section['title'] : ''); ?>" style="width: 100%;" />
            </p>

            <?php
            $fdp_widgets_json = isset($section['widgets_json']) ? $section['widgets_json'] : '[]';
            if (empty($fdp_widgets_json)) {
                $fdp_widgets_json = '[]';
            }
            $fdp_content_val = isset($section['content']) ? $section['content'] : '';
            $fdp_has_widgets = ($fdp_widgets_json !== '[]' && !empty($fdp_widgets_json));
            $fdp_has_code = !empty($fdp_content_val);
            $fdp_active_tab = isset($section['active_tab']) ? $section['active_tab'] : ($fdp_has_widgets || !$fdp_has_code ? 'widget' : 'code');
            $fdp_widget_style = ($fdp_active_tab === 'widget') ? '' : 'display:none;';
            $fdp_code_style = ($fdp_active_tab === 'code') ? '' : 'display:none;';
            ?>
            <div style="margin-bottom: 15px;">
                <label><strong><?php _e('Section Content Builder', 'fluent-dynamic-pages'); ?></strong></label><br>
                <div class="fdp-editor-tabs" style="margin-top: 5px;">
                    <button type="button" class="fdp-tab-btn <?php echo ($fdp_active_tab === 'widget') ? 'active' : ''; ?>"
                        data-target="widget">&#x1F9E9; Widget Builder</button>
                    <button type="button" class="fdp-tab-btn <?php echo ($fdp_active_tab === 'code') ? 'active' : ''; ?>"
                        data-target="code">Code Builder</button>
                    <button type="button" class="fdp-tab-btn" data-target="preview">Live Preview</button>
                </div>

                <!-- Widget Builder Pane -->
                <div class="fdp-editor-pane widget" style="<?php echo $fdp_widget_style; ?>">
                    <input type="hidden" class="fdp-active-tab-input" name="fdp_sections[<?php echo $index; ?>][active_tab]"
                        value="<?php echo esc_attr($fdp_active_tab); ?>">
                    <div class="fdp-widget-list"></div>
                    <div class="fdp-widget-toolbar">
                        <button type="button" class="button button-primary fdp-open-palette">&#43; Add Widget</button>
                    </div>
                    <textarea class="fdp-widgets-json-store" name="fdp_sections[<?php echo $index; ?>][widgets_json]"
                        style="display:none;"><?php echo esc_textarea($fdp_widgets_json); ?></textarea>
                </div>

                <!-- Code Builder Pane -->
                <div class="fdp-editor-pane code" style="<?php echo $fdp_code_style; ?>">
                    <textarea id="fdp_section_content_<?php echo $index; ?>" class="fdp-editor-textarea"
                        name="fdp_sections[<?php echo $index; ?>][content]" rows="10"
                        style="width: 100%; font-family: monospace;"><?php echo esc_textarea($fdp_content_val); ?></textarea>
                </div>

                <!-- Live Preview Pane -->
                <div class="fdp-editor-pane preview"></div>
            </div>

            <div style="background: #f0f0f1; padding: 10px; border: 1px solid #c3c4c7;">
                <p style="margin-top:0;"><strong><?php _e('Display Conditions', 'fluent-dynamic-pages'); ?></strong></p>
                <p>
                    <?php _e('Show this section if', 'fluent-dynamic-pages'); ?>
                    <select name="fdp_sections[<?php echo $index; ?>][condition_match]">
                        <option value="all" <?php selected(isset($section['condition_match']) ? $section['condition_match'] : '', 'all'); ?>><?php _e('ALL', 'fluent-dynamic-pages'); ?></option>
                        <option value="any" <?php selected(isset($section['condition_match']) ? $section['condition_match'] : '', 'any'); ?>><?php _e('ANY', 'fluent-dynamic-pages'); ?></option>
                    </select>
                    <?php _e('of the following rules are met:', 'fluent-dynamic-pages'); ?>
                </p>

                <div class="fdp-conditions-list" data-section-index="<?php echo $index; ?>">
                    <?php
                    $conditions = isset($section['conditions']) && is_array($section['conditions']) ? $section['conditions'] : array();

                    foreach ($conditions as $c_index => $condition) {
                        ?>
                        <div class="fdp-condition-row">
                            <select class="fdp-field-select"
                                name="fdp_sections[<?php echo $index; ?>][conditions][<?php echo $c_index; ?>][field]"
                                data-selected="<?php echo esc_attr($condition['field']); ?>" style="width:150px;">
                                <option value=""><?php _e('Select Field...', 'fluent-dynamic-pages'); ?></option>
                                <?php if (!empty($condition['field'])): ?>
                                    <option value="<?php echo esc_attr($condition['field']); ?>" selected>
                                        <?php echo esc_html($condition['field']); ?>
                                    </option>
                                <?php endif; ?>
                            </select>
                            <select name="fdp_sections[<?php echo $index; ?>][conditions][<?php echo $c_index; ?>][operator]">
                                <option value="equals" <?php selected($condition['operator'], 'equals'); ?>>
                                    <?php _e('Equals', 'fluent-dynamic-pages'); ?>
                                </option>
                                <option value="not_equals" <?php selected($condition['operator'], 'not_equals'); ?>>
                                    <?php _e('Not Equals', 'fluent-dynamic-pages'); ?>
                                </option>
                                <option value="greater_than" <?php selected($condition['operator'], 'greater_than'); ?>>
                                    <?php _e('Greater Than', 'fluent-dynamic-pages'); ?>
                                </option>
                                <option value="less_than" <?php selected($condition['operator'], 'less_than'); ?>>
                                    <?php _e('Less Than', 'fluent-dynamic-pages'); ?>
                                </option>
                                <option value="contains" <?php selected($condition['operator'], 'contains'); ?>>
                                    <?php _e('Contains', 'fluent-dynamic-pages'); ?>
                                </option>
                            </select>
                            <input type="text" class="fdp-value-input"
                                name="fdp_sections[<?php echo $index; ?>][conditions][<?php echo $c_index; ?>][value]"
                                value="<?php echo esc_attr($condition['value']); ?>"
                                data-value="<?php echo esc_attr($condition['value']); ?>"
                                placeholder="<?php _e('Value', 'fluent-dynamic-pages'); ?>" />
                            <span class="fdp-remove-condition"
                                title="<?php _e('Remove rule', 'fluent-dynamic-pages'); ?>">&times;</span>
                        </div>
                        <?php
                    }
                    ?>
                </div>
                <button type="button" class="button fdp-add-condition"
                    style="margin-top:5px;"><?php _e('+ Add Rule', 'fluent-dynamic-pages'); ?></button>
            </div>
        </div>
        <?php
        return ob_get_clean();
    }

    public function save_meta_boxes($post_id)
    {
        if (!isset($_POST['fdp_meta_box_nonce'])) {
            return;
        }
        if (!wp_verify_nonce($_POST['fdp_meta_box_nonce'], 'fdp_save_meta_box_data')) {
            return;
        }
        if (defined('DOING_AUTOSAVE') && DOING_AUTOSAVE) {
            return;
        }
        if (!current_user_can('edit_post', $post_id)) {
            return;
        }

        if (isset($_POST['fdp_mapped_form_id'])) {
            $form_id = sanitize_text_field($_POST['fdp_mapped_form_id']);
            update_post_meta($post_id, '_fdp_mapped_form_id', $form_id);
        }

        if (isset($_POST['fdp_static_content'])) {
            $static_content = current_user_can('unfiltered_html') ? $_POST['fdp_static_content'] : wp_slash(wp_kses_post(wp_unslash($_POST['fdp_static_content'])));
            update_post_meta($post_id, '_fdp_static_content', $static_content);
        }

        if (isset($_POST['fdp_heading_settings'])) {
            $heading_settings = array(
                'text' => sanitize_text_field($_POST['fdp_heading_settings']['text']),
                'tag' => sanitize_text_field($_POST['fdp_heading_settings']['tag']),
                'color' => sanitize_text_field($_POST['fdp_heading_settings']['color']),
                'align' => sanitize_text_field($_POST['fdp_heading_settings']['align']),
                'hide_title' => isset($_POST['fdp_heading_settings']['hide_title']) ? 1 : 0,
            );
            update_post_meta($post_id, '_fdp_heading_settings', $heading_settings);
        }

        if (isset($_POST['fdp_sections']) && is_array($_POST['fdp_sections'])) {
            $sections = array();
            foreach ($_POST['fdp_sections'] as $key => $section) {
                if ($key === '{INDEX}') {
                    continue;
                }

                $raw_content = $section['content'];
                $clean_content = current_user_can('unfiltered_html') ? $raw_content : wp_slash(wp_kses_post(wp_unslash($raw_content)));

                $clean_section = array(
                    'title' => sanitize_text_field($section['title']),
                    'content' => $clean_content,
                    'widgets_json' => isset($section['widgets_json']) ? $section['widgets_json'] : '[]',
                    'active_tab' => isset($section['active_tab']) ? sanitize_text_field($section['active_tab']) : 'widget',
                    'condition_match' => sanitize_text_field($section['condition_match']),
                    'conditions' => array()
                );

                if (isset($section['conditions']) && is_array($section['conditions'])) {
                    foreach ($section['conditions'] as $condition) {
                        if (!empty($condition['field'])) {
                            $clean_section['conditions'][] = array(
                                'field' => sanitize_text_field($condition['field']),
                                'operator' => sanitize_text_field($condition['operator']),
                                'value' => sanitize_text_field($condition['value']),
                            );
                        }
                    }
                }

                $sections[] = $clean_section;
            }
            update_post_meta($post_id, '_fdp_dynamic_sections', $sections);
        } else {
            update_post_meta($post_id, '_fdp_dynamic_sections', array());
        }
    }

    public function ajax_get_form_fields()
    {
        check_ajax_referer('fdp_admin_nonce', 'nonce');

        $form_id = isset($_POST['form_id']) ? intval($_POST['form_id']) : 0;
        if (!$form_id) {
            wp_send_json_error('Invalid Form ID');
        }

        global $wpdb;
        $forms_table = $wpdb->prefix . 'fluentform_forms';
        $form = $wpdb->get_row($wpdb->prepare("SELECT form_fields FROM {$forms_table} WHERE id = %d", $form_id));

        if (!$form) {
            wp_send_json_error('Form not found');
        }

        $fields_data = json_decode($form->form_fields, true);
        if (!$fields_data || !isset($fields_data['fields'])) {
            wp_send_json_error('No fields found');
        }

        $fields_list = array();
        $this->extract_fields($fields_data['fields'], $fields_list);

        wp_send_json_success($fields_list);
    }

    private function extract_fields($fields, &$fields_list)
    {
        foreach ($fields as $field) {
            if (isset($field['attributes']['name'])) {
                $name = $field['attributes']['name'];
                $label = isset($field['settings']['label']) ? $field['settings']['label'] : $name;
                $element = isset($field['element']) ? $field['element'] : '';

                $options = array();
                if (isset($field['settings']['advanced_options'])) {
                    $options = $field['settings']['advanced_options'];
                } elseif (isset($field['options'])) {
                    $options = $field['options'];
                }

                $fields_list[] = array(
                    'name' => $name,
                    'label' => $label,
                    'options' => $options
                );

                if ($element === 'input_name') {
                    $fields_list[] = array('name' => $name . '.first_name', 'label' => $label . ' (First Name)');
                    $fields_list[] = array('name' => $name . '.last_name', 'label' => $label . ' (Last Name)');
                    $fields_list[] = array('name' => $name . '.middle_name', 'label' => $label . ' (Middle Name)');
                } else if ($element === 'address') {
                    $fields_list[] = array('name' => $name . '.address_line_1', 'label' => $label . ' (Address Line 1)');
                    $fields_list[] = array('name' => $name . '.address_line_2', 'label' => $label . ' (Address Line 2)');
                    $fields_list[] = array('name' => $name . '.city', 'label' => $label . ' (City)');
                    $fields_list[] = array('name' => $name . '.state', 'label' => $label . ' (State)');
                    $fields_list[] = array('name' => $name . '.zip', 'label' => $label . ' (Zip)');
                    $fields_list[] = array('name' => $name . '.country', 'label' => $label . ' (Country)');
                }
            }
            if (isset($field['fields']) && is_array($field['fields'])) {
                $this->extract_fields($field['fields'], $fields_list);
            }
        }
    }
}
