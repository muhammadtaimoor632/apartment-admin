<?php
/**
 * Cleaning Checklist module — "Finish Cleaning" popup.
 *
 * Drop-in include for the Apartment Admin API plugin.
 *
 * To enable:
 *   1. Place this file at: includes/cleaning-checklist.php (relative to the main plugin file).
 *   2. In the main plugin file (apartment-admin.php), add near the top
 *      (after the ABSPATH guard):
 *
 *          require_once plugin_dir_path(__FILE__) . 'includes/cleaning-checklist.php';
 *
 *   3. Bump $version in aa_check_db_version() (e.g. '3.3.0' → '3.4.0') so
 *      the new table is created on next admin page load. Or visit
 *      Settings → Apartment Admin → Diagnostics → "Force Re-Create Tables".
 *
 * Routes (namespace: apartment_admin/v1):
 *   POST /cleaning-checklist/save
 *   GET  /cleaning-checklist/get?apartment_id=...&date=YYYY-MM-DD
 *   GET  /cleaning-checklist/list?apartment_id=...&limit=30
 */

if (!defined('ABSPATH')) {
    exit;
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. TABLE CREATION
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Hook our table into the existing aa_create_tables() routine so the
 * shared admin "Force Re-Create Tables" button creates this one too.
 *
 * Uses the same dbDelta pattern and $wpdb->prefix as the other tables.
 */
add_action('aa_create_tables_extra', 'aa_create_cleaning_checklist_table');

function aa_create_cleaning_checklist_table()
{
    global $wpdb;
    $charset = $wpdb->get_charset_collate();
    $table   = $wpdb->prefix . 'apartment_cleaning_checklists';

    $sql = "CREATE TABLE IF NOT EXISTS $table (
        id                    BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
        apartment_id          VARCHAR(100) NOT NULL,
        checklist_date        DATE         NOT NULL,
        towels_left_on_bed    INT          NOT NULL DEFAULT 0,
        code_set              TINYINT(1)   NOT NULL DEFAULT 0,
        parking_pass_checked  TINYINT(1)   NOT NULL DEFAULT 0,
        water_filled          TINYINT(1)   NOT NULL DEFAULT 0,
        submitted_at          DATETIME     DEFAULT NULL,
        created_at            DATETIME     DEFAULT CURRENT_TIMESTAMP,
        updated_at            DATETIME     DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        UNIQUE KEY apartment_date (apartment_id, checklist_date),
        KEY apartment_id (apartment_id),
        KEY checklist_date (checklist_date)
    ) $charset;";

    require_once ABSPATH . 'wp-admin/includes/upgrade.php';
    dbDelta($sql);
}

/**
 * Safety net: if the host plugin fires aa_create_tables() directly without
 * the do_action() hook (older deploys), still ensure the table exists once.
 */
add_action('plugins_loaded', 'aa_cleaning_checklist_ensure_table', 20);
function aa_cleaning_checklist_ensure_table()
{
    global $wpdb;
    $table = $wpdb->prefix . 'apartment_cleaning_checklists';
    $exists = $wpdb->get_var($wpdb->prepare("SHOW TABLES LIKE %s", $table)) === $table;
    if (!$exists) {
        aa_create_cleaning_checklist_table();
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. REST ROUTES
// ─────────────────────────────────────────────────────────────────────────────

add_action('rest_api_init', 'aa_register_cleaning_checklist_routes');

function aa_register_cleaning_checklist_routes()
{
    $ns = 'apartment_admin/v1';

    register_rest_route($ns, '/cleaning-checklist/save', [
        'methods'             => 'POST',
        'callback'            => 'aa_save_cleaning_checklist',
        'permission_callback' => 'aa_check_auth',
    ]);

    register_rest_route($ns, '/cleaning-checklist/get', [
        'methods'             => 'GET',
        'callback'            => 'aa_get_cleaning_checklist',
        'permission_callback' => 'aa_check_auth',
    ]);

    register_rest_route($ns, '/cleaning-checklist/list', [
        'methods'             => 'GET',
        'callback'            => 'aa_list_cleaning_checklists',
        'permission_callback' => 'aa_check_auth',
    ]);
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. CALLBACKS
// ─────────────────────────────────────────────────────────────────────────────

function aa_save_cleaning_checklist(WP_REST_Request $request)
{
    global $wpdb;
    $table = $wpdb->prefix . 'apartment_cleaning_checklists';

    $apartment_id = sanitize_text_field($request->get_param('apartment_id'));
    $date         = sanitize_text_field($request->get_param('date'));

    if (empty($apartment_id)) {
        return new WP_Error('missing_param', 'apartment_id is required.', ['status' => 400]);
    }
    if (empty($date) || !preg_match('/^\d{4}-\d{2}-\d{2}$/', $date)) {
        $date = current_time('Y-m-d');
    }

    $towels       = max(0, (int) $request->get_param('towels_left_on_bed'));
    $code_set     = (bool) $request->get_param('code_set') ? 1 : 0;
    $parking_pass = (bool) $request->get_param('parking_pass_checked') ? 1 : 0;
    $water_filled = (bool) $request->get_param('water_filled') ? 1 : 0;

    $submitted_raw = $request->get_param('submitted_at');
    $ts = !empty($submitted_raw) ? strtotime($submitted_raw) : false;
    $submitted_at = $ts ? gmdate('Y-m-d H:i:s', $ts) : current_time('mysql');

    $data = [
        'apartment_id'         => $apartment_id,
        'checklist_date'       => $date,
        'towels_left_on_bed'   => $towels,
        'code_set'             => $code_set,
        'parking_pass_checked' => $parking_pass,
        'water_filled'         => $water_filled,
        'submitted_at'         => $submitted_at,
    ];
    $formats = ['%s', '%s', '%d', '%d', '%d', '%d', '%s'];

    $existing_id = $wpdb->get_var($wpdb->prepare(
        "SELECT id FROM $table WHERE apartment_id = %s AND checklist_date = %s",
        $apartment_id,
        $date
    ));

    if ($existing_id) {
        $result = $wpdb->update($table, $data, ['id' => $existing_id], $formats, ['%d']);
        $row_id = $existing_id;
    } else {
        $result = $wpdb->insert($table, $data, $formats);
        $row_id = $wpdb->insert_id;
    }

    if ($result === false) {
        return new WP_Error('db_error', 'Failed to save checklist: ' . $wpdb->last_error, ['status' => 500]);
    }

    return rest_ensure_response([
        'success' => true,
        'id'      => (int) $row_id,
        'data'    => $data,
    ]);
}

function aa_get_cleaning_checklist(WP_REST_Request $request)
{
    global $wpdb;
    $table = $wpdb->prefix . 'apartment_cleaning_checklists';

    $apartment_id = sanitize_text_field($request->get_param('apartment_id'));
    $date         = sanitize_text_field($request->get_param('date'));
    if (empty($date) || !preg_match('/^\d{4}-\d{2}-\d{2}$/', $date)) {
        $date = current_time('Y-m-d');
    }

    if (empty($apartment_id)) {
        return new WP_Error('missing_param', 'apartment_id is required.', ['status' => 400]);
    }

    $row = $wpdb->get_row($wpdb->prepare(
        "SELECT * FROM $table WHERE apartment_id = %s AND checklist_date = %s",
        $apartment_id,
        $date
    ), ARRAY_A);

    if (!$row) {
        return rest_ensure_response(['found' => false]);
    }

    return rest_ensure_response([
        'found'                => true,
        'id'                   => (int) $row['id'],
        'apartment_id'         => $row['apartment_id'],
        'date'                 => $row['checklist_date'],
        'towels_left_on_bed'   => (int) $row['towels_left_on_bed'],
        'code_set'             => (bool) $row['code_set'],
        'parking_pass_checked' => (bool) $row['parking_pass_checked'],
        'water_filled'         => (bool) $row['water_filled'],
        'submitted_at'         => $row['submitted_at'],
    ]);
}

function aa_list_cleaning_checklists(WP_REST_Request $request)
{
    global $wpdb;
    $table = $wpdb->prefix . 'apartment_cleaning_checklists';

    $apartment_id = sanitize_text_field($request->get_param('apartment_id'));
    $limit        = max(1, min(100, (int) ($request->get_param('limit') ?: 30)));

    if (empty($apartment_id)) {
        return new WP_Error('missing_param', 'apartment_id is required.', ['status' => 400]);
    }

    $rows = $wpdb->get_results($wpdb->prepare(
        "SELECT * FROM $table WHERE apartment_id = %s ORDER BY checklist_date DESC LIMIT %d",
        $apartment_id,
        $limit
    ), ARRAY_A);

    $out = array_map(function ($row) {
        return [
            'id'                   => (int) $row['id'],
            'apartment_id'         => $row['apartment_id'],
            'date'                 => $row['checklist_date'],
            'towels_left_on_bed'   => (int) $row['towels_left_on_bed'],
            'code_set'             => (bool) $row['code_set'],
            'parking_pass_checked' => (bool) $row['parking_pass_checked'],
            'water_filled'         => (bool) $row['water_filled'],
            'submitted_at'         => $row['submitted_at'],
        ];
    }, $rows ?: []);

    return rest_ensure_response($out);
}
