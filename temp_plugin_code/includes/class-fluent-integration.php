<?php
if (!defined('ABSPATH')) {
    exit;
}

class FDP_Fluent_Integration
{

    private $table_name;
    private $generated_links = array();
    private $last_generated_link = '';

    public function __construct()
    {
        global $wpdb;
        $this->table_name = $wpdb->prefix . 'fdp_generated_links';

        add_action('init', array($this, 'maybe_create_table'));

        // Hook into Fluent Forms submission
        add_filter('fluentform/insert_response_data', array($this, 'inject_dynamic_link'), 10, 3);
        add_filter('fluentform_insert_response_data', array($this, 'inject_dynamic_link'), 10, 3);
        add_action('fluentform_submission_inserted', array($this, 'record_generated_link'), 10, 3);
        add_action('fluentform/submission_inserted', array($this, 'record_generated_link'), 10, 3);

        // Register shortcodes
        add_shortcode('fluent_dynamic', array($this, 'render_dynamic_field'));
        add_shortcode('fluent_if', array($this, 'render_conditional_content'));
        add_shortcode('fdp_video', array($this, 'render_video_shortcode'));
        add_shortcode('fdp_popup_button', array($this, 'render_popup_button'));

        // Register Fluent Forms smartcodes for emails/confirmations
        add_filter('fluentform/all_editor_shortcodes', array($this, 'register_fluent_smartcode'));
        add_filter('fluentform/shortcode_parser_callback_dynamic_page_link', array($this, 'parse_fluent_smartcode'), 10, 4);
        add_filter('fluentform_shortcode_parser_callback_dynamic_page_link', array($this, 'parse_fluent_smartcode'), 10, 4);

        // Hook into the_content to render Visual Sections
        add_filter('the_content', array($this, 'append_dynamic_sections'));

        // Enqueue frontend widget styles/scripts and output video modal HTML
        add_action('wp_enqueue_scripts', array($this, 'enqueue_frontend_assets'));
        add_action('wp_footer', array($this, 'render_video_modal'));

    }

    public function maybe_create_table()
    {
        if (get_option('fdp_db_version') !== FF_DYNAMIC_PAGES_VERSION) {
            global $wpdb;
            $charset_collate = $wpdb->get_charset_collate();

            $sql = "CREATE TABLE $this->table_name (
                id bigint(20) NOT NULL AUTO_INCREMENT,
                post_id bigint(20) NOT NULL,
                form_id bigint(20) NOT NULL,
                submission_id bigint(20) NOT NULL,
                hash varchar(64) NOT NULL,
                created_at datetime DEFAULT '0000-00-00 00:00:00' NOT NULL,
                PRIMARY KEY  (id),
                KEY post_id (post_id),
                KEY submission_id (submission_id),
                KEY hash (hash)
            ) $charset_collate;";

            require_once(ABSPATH . 'wp-admin/includes/upgrade.php');
            dbDelta($sql);

            update_option('fdp_db_version', FF_DYNAMIC_PAGES_VERSION);
        }
    }

    public function inject_dynamic_link($data, $formId, $formData)
    {
        global $wpdb;
        $mapped_page_id = $wpdb->get_var($wpdb->prepare(
            "SELECT post_id FROM {$wpdb->postmeta} pm JOIN {$wpdb->posts} p ON p.ID = pm.post_id WHERE p.post_type = 'fluent_dynamic_page' AND p.post_status = 'publish' AND pm.meta_key = '_fdp_mapped_form_id' AND pm.meta_value = %s ORDER BY p.ID DESC LIMIT 1",
            $formId
        ));

        if ($mapped_page_id) {
            $post_id = $mapped_page_id;
            $hash = wp_generate_password(32, false);
            $url = add_query_arg('fdp_hash', $hash, get_permalink($post_id));

            $data['dynamic_page_link'] = $url;
            $data['fdp_hash'] = $hash;
            $data['fdp_post_id'] = $post_id;
            $data['fdp_form_id'] = $formId;

            $this->generated_links[$formId] = $url;
            $this->last_generated_link = $url;
        }

        return $data;
    }

    public function record_generated_link($insertId, $formData = null, $form = null)
    {
        global $wpdb;
        $submission = $wpdb->get_row($wpdb->prepare("SELECT response FROM {$wpdb->prefix}fluentform_submissions WHERE id = %d", $insertId));

        $form_id = is_object($form) ? $form->id : (is_array($form) && isset($form['id']) ? $form['id'] : 0);

        if ($submission && $submission->response) {
            $response_data = json_decode($submission->response, true);

            // Generate link dynamically here if it missed the earlier hook!
            if (!isset($response_data['fdp_hash'])) {
                $mapped_page_id = $wpdb->get_var($wpdb->prepare(
                    "SELECT post_id FROM {$wpdb->postmeta} pm JOIN {$wpdb->posts} p ON p.ID = pm.post_id WHERE p.post_type = 'fluent_dynamic_page' AND p.post_status = 'publish' AND pm.meta_key = '_fdp_mapped_form_id' AND pm.meta_value = %s ORDER BY p.ID DESC LIMIT 1",
                    $form_id
                ));

                if ($mapped_page_id) {
                    $post_id = $mapped_page_id;
                    $hash = wp_generate_password(32, false);
                    $url = add_query_arg('fdp_hash', $hash, get_permalink($post_id));

                    $response_data['dynamic_page_link'] = $url;
                    $response_data['fdp_hash'] = $hash;
                    $response_data['fdp_post_id'] = $post_id;

                    // Update DB with the new response data
                    $wpdb->update(
                        "{$wpdb->prefix}fluentform_submissions",
                        array('response' => json_encode($response_data)),
                        array('id' => $insertId)
                    );

                    $this->generated_links[$form_id] = $url;
                    $this->last_generated_link = $url;
                }
            }

            if (isset($response_data['fdp_hash']) && isset($response_data['fdp_post_id'])) {
                $exists = $wpdb->get_var($wpdb->prepare("SELECT id FROM {$this->table_name} WHERE submission_id = %d", $insertId));
                if (!$exists) {
                    $wpdb->insert(
                        $this->table_name,
                        array(
                            'post_id' => $response_data['fdp_post_id'],
                            'form_id' => $form_id,
                            'submission_id' => $insertId,
                            'hash' => $response_data['fdp_hash'],
                            'created_at' => current_time('mysql')
                        )
                    );
                }
            }
        }
    }

    public function register_fluent_smartcode($smartcodes)
    {
        // Register {dynamic_page_link} in the General section or as a standalone key
        $smartcodes['General']['{dynamic_page_link}'] = 'Dynamic Webpage Link';
        return $smartcodes;
    }

    public function parse_fluent_smartcode($value, $form = null, $entry = null, $shortCodeKey = null)
    {
        // 1. In-memory fallback (best for immediate synchronous requests)
        if ($this->last_generated_link) {
            return $this->last_generated_link;
        }

        $form_id_to_check = is_object($form) ? $form->id : (is_array($form) && isset($form['id']) ? $form['id'] : null);
        if ($form_id_to_check && isset($this->generated_links[$form_id_to_check])) {
            return $this->generated_links[$form_id_to_check];
        }

        if (!$entry) {
            return '';
        }

        // 2. Check within the entry's response data
        $response_data = array();
        if (is_object($entry) && isset($entry->response)) {
            $response_data = json_decode($entry->response, true);
        } else if (is_array($entry) && isset($entry['response'])) {
            $response_data = json_decode($entry['response'], true);
        } else if (is_array($entry)) {
            $response_data = $entry;
        }

        if (isset($response_data['dynamic_page_link'])) {
            return $response_data['dynamic_page_link'];
        }

        // Fallback: look up in the DB table
        global $wpdb;
        $entry_id = (is_object($entry) && isset($entry->id)) ? $entry->id : ((is_array($entry) && isset($entry['id'])) ? $entry['id'] : null);
        if ($entry_id) {
            $link_record = $wpdb->get_row($wpdb->prepare(
                "SELECT post_id, hash FROM {$this->table_name} WHERE submission_id = %d",
                $entry_id
            ));
            if ($link_record) {
                return add_query_arg('fdp_hash', $link_record->hash, get_permalink($link_record->post_id));
            }
        }

        return '';
    }

    private function get_nested_value($data, $key)
    {
        $keys = explode('.', $key);
        foreach ($keys as $k) {
            if (is_array($data) && isset($data[$k])) {
                $data = $data[$k];
            } else {
                return '';
            }
        }
        return $data;
    }

    public function render_dynamic_field($atts)
    {
        $atts = shortcode_atts(array(
            'field' => '',
            'math_add' => '',
        ), $atts, 'fluent_dynamic');

        if (empty($atts['field'])) {
            return '';
        }

        $submission_data = $this->get_current_submission_data();
        if (!$submission_data) {
            if (current_user_can('edit_posts')) {
                return '<span style="background:#eee; padding:2px 5px; border-radius:3px;">[' . esc_html($atts['field']) . ']</span>';
            }
            return '';
        }

        $val = $this->get_nested_value($submission_data, $atts['field']);
        if (is_array($val)) {
            $val = implode(', ', $val);
        }

        if (!empty($atts['math_add']) && is_numeric($atts['math_add'])) {
            $numeric_val = preg_replace('/[^0-9.]/', '', $val);
            if (is_numeric($numeric_val)) {
                $val = floatval($numeric_val) + floatval($atts['math_add']);
            }
        }

        return esc_html($val);
    }

    public function render_conditional_content($atts, $content = null)
    {
        $atts = shortcode_atts(array(
            'field' => '',
            'condition' => 'equals',
            'value' => '',
        ), $atts, 'fluent_if');

        if (empty($atts['field'])) {
            return '';
        }

        $submission_data = $this->get_current_submission_data();
        if (!$submission_data) {
            if (current_user_can('edit_posts')) {
                return '<div style="border:1px dashed #ccc; padding:10px; margin: 10px 0;"><strong>[If ' . esc_html($atts['field']) . ' ' . esc_html($atts['condition']) . ' ' . esc_html($atts['value']) . ']</strong><br>' . do_shortcode($content) . '</div>';
            }
            return '';
        }

        $actual_value = $this->get_nested_value($submission_data, $atts['field']);
        $expected_value = $atts['value'];
        $show = $this->evaluate_condition($actual_value, $atts['condition'], $expected_value);

        if ($show) {
            return do_shortcode($content);
        }

        return '';
    }

    public function render_video_shortcode($atts, $content = null)
    {
        $atts = shortcode_atts(array(
            'url' => '',
        ), $atts, 'fdp_video');

        if (empty($atts['url'])) {
            return do_shortcode($content);
        }

        return '<a href="#" class="fdp-video-link" data-video-url="' . esc_attr($atts['url']) . '">' . do_shortcode($content) . '</a>';
    }

    public function render_popup_button($atts, $content = null)
    {
        $atts = shortcode_atts(array(
            'class' => '',
        ), $atts, 'fdp_popup_button');

        $class = 'fdp-popup-trigger-btn ' . esc_attr($atts['class']);
        return '<button type="button" class="' . $class . '">' . do_shortcode($content) . '</button>';
    }

    public function enqueue_frontend_assets()
    {
        if (!is_singular('fluent_dynamic_page')) {
            return;
        }
        $css_ver = file_exists(FF_DYNAMIC_PAGES_DIR . 'assets/frontend.css')
            ? filemtime(FF_DYNAMIC_PAGES_DIR . 'assets/frontend.css')
            : FF_DYNAMIC_PAGES_VERSION;
        $js_ver = file_exists(FF_DYNAMIC_PAGES_DIR . 'assets/frontend.js')
            ? filemtime(FF_DYNAMIC_PAGES_DIR . 'assets/frontend.js')
            : FF_DYNAMIC_PAGES_VERSION;
        wp_enqueue_style(
            'fdp-frontend-css',
            FF_DYNAMIC_PAGES_URL . 'assets/frontend.css',
            array(),
            $css_ver
        );
        wp_enqueue_script(
            'fdp-frontend-js',
            FF_DYNAMIC_PAGES_URL . 'assets/frontend.js',
            array(),
            $js_ver,
            true
        );
    }

    public function render_video_modal()
    {
        if (!is_singular('fluent_dynamic_page')) {
            return;
        }
        echo '<div class="fdp-video-modal" id="fdp-video-modal" aria-modal="true" role="dialog">';
        echo '  <div class="fdp-modal-inner">';
        echo '    <button class="fdp-modal-close" id="fdp-modal-close" aria-label="Close video">&times; Close</button>';
        echo '    <div class="fdp-video-embed">';
        echo '      <iframe id="fdp-video-player" src="" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture" allowfullscreen></iframe>';
        echo '    </div>';
        echo '  </div>';
        echo '</div>';
    }



    public function append_dynamic_sections($content)
    {
        if (!is_singular('fluent_dynamic_page')) {
            return $content;
        }

        global $post;
        if (!$post || $post->post_type !== 'fluent_dynamic_page') {
            return $content;
        }

        $sections = get_post_meta($post->ID, '_fdp_dynamic_sections', true);
        $static_content = get_post_meta($post->ID, '_fdp_static_content', true);
        $heading_settings = get_post_meta($post->ID, '_fdp_heading_settings', true);

        $appended_content = '';

        if (!empty($heading_settings) && !empty($heading_settings['hide_title'])) {
            $appended_content .= '<style>.entry-title, .page-title, .post-title, h1.title, .entry-header, .fdp-page-title { display: none !important; }</style>';
        }

        if (!empty($heading_settings) && !empty($heading_settings['text'])) {
            $tag = isset($heading_settings['tag']) ? $heading_settings['tag'] : 'h1';
            $color = isset($heading_settings['color']) ? $heading_settings['color'] : '';
            $align = isset($heading_settings['align']) ? $heading_settings['align'] : 'left';
            $style = '';
            if ($color) {
                $style .= 'color: ' . esc_attr($color) . ' !important; ';
            }
            if ($align) {
                $style .= 'text-align: ' . esc_attr($align) . '; ';
            }

            $appended_content .= '<' . esc_attr($tag) . ' class="fdp-custom-heading" style="' . $style . '">' . do_shortcode($heading_settings['text']) . '</' . esc_attr($tag) . '>';
        }

        if (!empty($static_content)) {
            $appended_content .= '<div class="fdp-static-section">' . do_shortcode(wpautop($static_content)) . '</div>';
        }

        if (empty($sections) || !is_array($sections)) {
            return $content . $appended_content;
        }

        $submission_data = $this->get_current_submission_data();
        $is_admin_preview = (!$submission_data && current_user_can('edit_posts'));

        $dropdown_options = '';
        $conditional_sections_html = '';
        $global_sections_html = '';
        $default_visible_section_id = '';

        $conditional_sections_count = 0;
        foreach ($sections as $section) {
            $conditions = isset($section['conditions']) ? $section['conditions'] : array();
            if (!empty($conditions)) {
                $conditional_sections_count++;
            }
        }
        $has_multiple_conditional_sections = $conditional_sections_count > 1;

        foreach ($sections as $index => $section) {
            $section_title = isset($section['title']) && $section['title'] ? $section['title'] : 'Section ' . ($index + 1);
            $section_id = 'fdp-section-' . sanitize_title($section_title) . '-' . $index;

            $conditions = isset($section['conditions']) ? $section['conditions'] : array();
            $is_global = empty($conditions);

            if ($is_global) {
                if ($is_admin_preview) {
                    $global_sections_html .= '<div style="border: 1px dashed #4caf50; padding: 15px; margin: 20px 0;" class="fdp-global-section" id="' . esc_attr($section_id) . '">';
                    $global_sections_html .= '<p style="color:#4caf50; font-size:12px; text-transform:uppercase; margin-top:0;"><strong>' . esc_html($section_title) . '</strong> <em>(Global Section: Always Visible)</em></p>';
                } else {
                    $global_sections_html .= '<div class="fdp-global-section" id="' . esc_attr($section_id) . '" style="display: block;">';
                    $global_sections_html .= '<div class="fdp-dynamic-section">';
                }

                $section_content = isset($section['content']) ? $section['content'] : '';
                $global_sections_html .= do_shortcode($section_content);

                if (!$is_admin_preview) {
                    $global_sections_html .= '</div></div>';
                } else {
                    $global_sections_html .= '</div>';
                }
            } else {
                $is_matched = false;

                if ($is_admin_preview) {
                    $is_matched = true;
                } else if ($submission_data) {
                    $match_type = isset($section['condition_match']) ? $section['condition_match'] : 'all';
                    $results = array();
                    foreach ($conditions as $condition) {
                        $actual_value = $this->get_nested_value($submission_data, $condition['field']);
                        $results[] = $this->evaluate_condition($actual_value, $condition['operator'], $condition['value']);
                    }

                    if ('all' === $match_type) {
                        $is_matched = !in_array(false, $results, true);
                    } else {
                        $is_matched = in_array(true, $results, true);
                    }
                }

                if ($is_matched && empty($default_visible_section_id)) {
                    $default_visible_section_id = $section_id;
                }

                $active_class = ($is_matched && $default_visible_section_id === $section_id) ? 'fdp-active' : '';
                $dropdown_options .= '<li class="' . $active_class . '" onclick="fdpChangeSection(\'' . esc_attr($section_id) . '\', this)">' . esc_html($section_title) . '</li>';

                $display_style = ($default_visible_section_id === $section_id || $is_admin_preview) ? 'display: block;' : 'display: none;';

                if ($is_admin_preview) {
                    $conditional_sections_html .= '<div style="border: 1px dashed #ccc; padding: 15px; margin: 20px 0;" class="fdp-dynamic-section-container" id="' . esc_attr($section_id) . '">';
                    $conditional_sections_html .= '<p style="color:#888; font-size:12px; text-transform:uppercase; margin-top:0;"><strong>' . esc_html($section_title) . '</strong> <em>(Admin Preview: Conditions ignored)</em></p>';
                } else {
                    $conditional_sections_html .= '<div class="fdp-dynamic-section-container" id="' . esc_attr($section_id) . '" style="' . $display_style . '">';
                    $conditional_sections_html .= '<div class="fdp-dynamic-section">';
                }

                $section_content = isset($section['content']) ? $section['content'] : '';
                $conditional_sections_html .= do_shortcode($section_content);

                if (!$is_admin_preview) {
                    $conditional_sections_html .= '</div></div>';
                } else {
                    $conditional_sections_html .= '</div>';
                }
            }
        }

        if (!$is_admin_preview && $has_multiple_conditional_sections) {
            $dropdown_html = '<div class="fdp-hamburger-menu">';
            $dropdown_html .= '<div class="fdp-hamburger-icon" onclick="fdpToggleMenu()">';
            $dropdown_html .= '<span></span><span></span><span></span>';
            $dropdown_html .= '</div>';
            $dropdown_html .= '<ul class="fdp-hamburger-dropdown" id="fdp-hamburger-dropdown">';
            $dropdown_html .= '<li class="fdp-dropdown-header">Change of plans</li>';
            if (empty($default_visible_section_id)) {
                $dropdown_html .= '<li class="fdp-active" onclick="fdpChangeSection(\'\', this)">-- Select a Section --</li>';
            }
            $dropdown_html .= $dropdown_options;
            $dropdown_html .= '</ul>';
            $dropdown_html .= '</div>';

            $dropdown_html .= '<style>
                .fdp-hamburger-menu {
                    position: fixed;
                    top: 20px;
                    right: 20px;
                    z-index: 99999;
                }
                .fdp-hamburger-icon {
                    width: 44px;
                    height: 44px;
                    background: #fff;
                    border-radius: 8px;
                    box-shadow: 0 4px 12px rgba(0,0,0,0.15);
                    display: flex;
                    flex-direction: column;
                    justify-content: center;
                    align-items: center;
                    cursor: pointer;
                    gap: 6px;
                    border: 1px solid #e2e8f0;
                    transition: background 0.2s;
                }
                .fdp-hamburger-icon:hover {
                    background: #f8fafc;
                }
                .fdp-hamburger-icon span {
                    width: 24px;
                    height: 3px;
                    background-color: #334155;
                    border-radius: 3px;
                    transition: 0.3s;
                }
                .fdp-hamburger-menu.fdp-open .fdp-hamburger-icon span:nth-child(1) {
                    transform: translateY(9px) rotate(45deg);
                }
                .fdp-hamburger-menu.fdp-open .fdp-hamburger-icon span:nth-child(2) {
                    opacity: 0;
                }
                .fdp-hamburger-menu.fdp-open .fdp-hamburger-icon span:nth-child(3) {
                    transform: translateY(-9px) rotate(-45deg);
                }
                .fdp-hamburger-dropdown {
                    display: none;
                    position: absolute;
                    top: 54px;
                    right: 0;
                    background: #fff;
                    box-shadow: 0 10px 25px rgba(0,0,0,0.15);
                    border-radius: 8px;
                    list-style: none;
                    padding: 8px 0;
                    margin: 0;
                    min-width: 240px;
                    border: 1px solid #e2e8f0;
                }
                .fdp-hamburger-menu.fdp-open .fdp-hamburger-dropdown {
                    display: block;
                    animation: fdpFadeIn 0.2s ease;
                }
                @keyframes fdpFadeIn {
                    from { opacity: 0; transform: translateY(-10px); }
                    to { opacity: 1; transform: translateY(0); }
                }
                .fdp-hamburger-dropdown li {
                    padding: 12px 20px;
                    cursor: pointer;
                    color: #334155;
                    font-size: 15px;
                    transition: background 0.2s;
                    border-bottom: 1px solid #f1f5f9;
                }
                .fdp-hamburger-dropdown li.fdp-dropdown-header {
                    display: block !important;
                    opacity: 1 !important;
                    visibility: visible !important;
                    padding: 10px 20px;
                    font-size: 13px;
                    font-weight: 700;
                    color: #64748b;
                    text-transform: uppercase;
                    letter-spacing: 0.5px;
                    border-bottom: 1px solid #e2e8f0;
                    margin-bottom: 4px;
                    pointer-events: none;
                    background: transparent;
                }
                .fdp-hamburger-dropdown li:last-child {
                    border-bottom: none;
                }
                .fdp-hamburger-dropdown li:hover {
                    background: #f8fafc;
                }
                .fdp-hamburger-dropdown li.fdp-active {
                    background: #eef2f6;
                    font-weight: 600;
                    color: #0f172a;
                    border-left: 3px solid #3b82f6;
                    padding-left: 17px;
                }
            </style>';

            $dropdown_html .= '<script>
                function fdpToggleMenu() {
                    var menu = document.querySelector(".fdp-hamburger-menu");
                    if (menu) menu.classList.toggle("fdp-open");
                }
                function fdpChangeSection(sectionId, element) {
                    var sections = document.querySelectorAll(".fdp-dynamic-section-container");
                    for (var i = 0; i < sections.length; i++) {
                        sections[i].style.display = "none";
                    }
                    if (sectionId) {
                        var activeSection = document.getElementById(sectionId);
                        if (activeSection) {
                            activeSection.style.display = "block";
                        }
                    }
                    
                    var items = document.querySelectorAll(".fdp-hamburger-dropdown li");
                    for (var j = 0; j < items.length; j++) {
                        items[j].classList.remove("fdp-active");
                    }
                    if (element) {
                        element.classList.add("fdp-active");
                    }
                    
                    fdpToggleMenu();
                }
                
                document.addEventListener("click", function(event) {
                    var menu = document.querySelector(".fdp-hamburger-menu");
                    if (menu && menu.classList.contains("fdp-open") && !menu.contains(event.target)) {
                        menu.classList.remove("fdp-open");
                    }
                });
            </script>';

            $appended_content .= $dropdown_html;
        }

        $appended_content .= $conditional_sections_html;
        $appended_content .= $global_sections_html;

        return $content . $appended_content;
    }

    private function evaluate_condition($actual_value, $operator, $expected_value)
    {
        if (is_array($actual_value)) {
            if ($operator === 'equals' || $operator === 'contains') {
                return in_array($expected_value, $actual_value);
            }
            if ($operator === 'not_equals') {
                return !in_array($expected_value, $actual_value);
            }
            $actual_value = implode(', ', $actual_value);
        }

        $actual_value = trim((string) $actual_value);
        $expected_value = trim((string) $expected_value);

        switch ($operator) {
            case 'equals':
                return ($actual_value === $expected_value);
            case 'not_equals':
                return ($actual_value !== $expected_value);
            case 'greater_than':
                return (floatval($actual_value) > floatval($expected_value));
            case 'less_than':
                return (floatval($actual_value) < floatval($expected_value));
            case 'contains':
                if ($expected_value === '') {
                    return true;
                }
                return (stripos($actual_value, $expected_value) !== false);
        }
        return false;
    }

    private function get_current_submission_data()
    {
        static $data = null;
        if ($data !== null) {
            return $data;
        }

        $hash = isset($_GET['fdp_hash']) ? sanitize_text_field($_GET['fdp_hash']) : '';
        if (empty($hash)) {
            $data = false;
            return $data;
        }

        global $post, $wpdb;
        if (!$post || $post->post_type !== 'fluent_dynamic_page') {
            $data = false;
            return $data;
        }

        $link_record = $wpdb->get_row($wpdb->prepare(
            "SELECT submission_id FROM {$this->table_name} WHERE hash = %s AND post_id = %d",
            $hash,
            $post->ID
        ));

        if (!$link_record) {
            $data = false;
            return $data;
        }

        $submission = $wpdb->get_row($wpdb->prepare(
            "SELECT response FROM {$wpdb->prefix}fluentform_submissions WHERE id = %d",
            $link_record->submission_id
        ));

        if ($submission && $submission->response) {
            $data = json_decode($submission->response, true);
        } else {
            $data = false;
        }

        return $data;
    }
}
