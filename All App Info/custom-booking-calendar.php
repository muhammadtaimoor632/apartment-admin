<?php
/**
 * Plugin Name: Custom Booking Calendar Sync
 * Description: Supports multiple separate calendars. Auto-syncs on page load to instantly pull Fluent Forms submissions into beautifully formatted popups. Includes room-specific matching, exact-match blocked date detection, persistent iCal history (never loses past bookings), automatic Fluent Forms entry cleanup on booking cancellation, and historical backfill from Fluent Forms for bookings that have already dropped off the iCal feeds.
 * Version: 9.8
 * Author: Jamie
 */
if (!defined('ABSPATH'))
    exit;

// ══════════════════════════════════════════════════════════════════
// SECTION 1 — ADMIN MENU & SETTINGS PAGE
// ══════════════════════════════════════════════════════════════════
add_action('admin_menu', 'cbc_add_admin_menu');
function cbc_add_admin_menu()
{
    add_menu_page(
        'Booking Calendars', 'Booking Sync',
        'manage_options', 'cbc-settings',
        'cbc_render_settings_page', 'dashicons-calendar-alt', 85
    );
    add_submenu_page(
        'cbc-settings',
        'Settings', 'Settings',
        'manage_options', 'cbc-settings',
        'cbc_render_settings_page'
    );
    add_submenu_page(
        'cbc-settings',
        'All Bookings', 'All Bookings',
        'manage_options', 'cbc-bookings-data',
        'cbc_render_bookings_data_page'
    );
}
add_action('admin_init', 'cbc_register_settings');
function cbc_register_settings()
{
    register_setting('cbc_settings_group', 'cbc_calendars');
}
function cbc_render_settings_page()
{
    $calendars = get_option('cbc_calendars', array());
    if (!is_array($calendars))
        $calendars = array();

    // Manual "purge stored history" handler (admin-only)
    if (isset($_GET['cbc_purge']) && current_user_can('manage_options') && check_admin_referer('cbc_purge_action', 'cbc_purge_nonce')) {
        $purge_id = sanitize_text_field($_GET['cbc_purge']);
        delete_option('cbc_stored_ical_' . $purge_id);
        delete_transient('cbc_events_' . $purge_id);
        echo '<div class="notice notice-success is-dismissible"><p>Stored iCal history cleared for that calendar.</p></div>';
    }

    if (isset($_GET['settings-updated']) && $_GET['settings-updated']) {
        foreach ($calendars as $cal_id => $cal) {
            delete_transient('cbc_events_' . $cal_id);
        }
    }

    // Auto-backfill empty room_names for existing records
    global $wpdb;
    $db_table = $wpdb->prefix . 'cbc_pricelabs_bookings_data';
    if ($wpdb->get_var("SHOW TABLES LIKE '$db_table'") == $db_table) {
        foreach ($calendars as $cal_id => $cal) {
            if (!empty($cal['rooms'])) {
                foreach ($cal['rooms'] as $room_id => $room) {
                    $r_name = isset($room['name']) ? $room['name'] : 'Unknown';
                    $wpdb->query($wpdb->prepare(
                        "UPDATE `$db_table` SET `room_name` = %s WHERE `room_id` = %s AND (`room_name` = '' OR `room_name` IS NULL)",
                        $r_name, $room_id
                    ));
                }
            }
        }
    }

    // Manual "add booking" handler
    if (isset($_POST['cbc_manual_insert']) && current_user_can('manage_options') && check_admin_referer('cbc_manual_action', 'cbc_manual_nonce')) {
        global $wpdb;
        $db_table = $wpdb->prefix . 'cbc_pricelabs_bookings_data';
        
        $cal_id     = sanitize_text_field($_POST['manual_cal_id']);
        $room_id    = sanitize_text_field($_POST['manual_room_id']);
        $start_date = sanitize_text_field($_POST['manual_start']);
        $end_date   = sanitize_text_field($_POST['manual_end']);
        $status     = sanitize_text_field($_POST['manual_status']);
        
        $room_name = isset($calendars[$cal_id]['rooms'][$room_id]['name']) ? $calendars[$cal_id]['rooms'][$room_id]['name'] : 'Manual Room';
        
        if ($cal_id && $room_id && $start_date && $end_date) {
            $uid = md5($cal_id . '_' . $room_id . '_pricelabs_' . $start_date . '_' . $end_date . '_manual');
            $nights = (int)round((strtotime($end_date) - strtotime($start_date)) / 86400);
            $current_time = current_time('mysql');
            
            $wpdb->query($wpdb->prepare(
                "INSERT INTO $db_table (cal_id, room_id, room_name, platform, start_date, end_date, summary, uid, nights, booked_on, status, is_blocked, last_seen) 
                 VALUES (%s, %s, %s, 'pricelabs', %s, %s, 'Manual Entry', %s, %d, %s, %s, 0, %s)
                 ON DUPLICATE KEY UPDATE 
                 status = VALUES(status), last_seen = VALUES(last_seen)",
                $cal_id, $room_id, $room_name, $start_date, $end_date, $uid, $nights, date('Y-m-d'), $status, $current_time
            ));
            
            delete_transient('cbc_events_' . $cal_id);
            echo '<div class="notice notice-success is-dismissible"><p>Manual booking successfully inserted into the database!</p></div>';
        } else {
            echo '<div class="notice notice-error is-dismissible"><p>Error: Please fill in all fields.</p></div>';
        }
    }
?>
    <div class="wrap">
        <h1>Booking Calendar Sync (Direct Database)</h1>

        <form method="post" action="options.php" id="cbc-settings-form">
            <?php settings_fields('cbc_settings_group'); ?>

            <div style="display: flex; justify-content: space-between; align-items: center; margin-top: 20px;">
                <h2>Your Calendars</h2>
                <button type="button" class="button button-primary" id="cbc-add-calendar">+ Add New Calendar</button>
            </div>

            <div id="cbc-calendars-container">
                <?php foreach ($calendars as $cal_id => $calendar): ?>
                    <div class="cbc-calendar-block" style="background: #fff; border: 1px solid #c3c4c7; padding: 20px; margin-top: 20px; border-radius: 4px; box-shadow: 0 1px 1px rgba(0,0,0,.04);">
                        <div style="display: flex; justify-content: space-between; border-bottom: 1px solid #eee; padding-bottom: 15px; margin-bottom: 15px;">
                            <div>
                                <strong>Calendar Name:</strong>
                                <input type="text" name="cbc_calendars[<?php echo esc_attr($cal_id); ?>][name]" value="<?php echo esc_attr(isset($calendar['name']) ? $calendar['name'] : 'New Calendar'); ?>" class="regular-text">
                                <br><span class="description" style="display:inline-block; margin-top:8px;">Shortcode: <code style="font-size:14px;">[custom_booking_calendar id="<?php echo esc_attr($cal_id); ?>"]</code></span>
                                <br>
                                <a href="<?php echo esc_url(wp_nonce_url(admin_url('admin.php?page=cbc-settings&cbc_purge=' . $cal_id), 'cbc_purge_action', 'cbc_purge_nonce')); ?>"
                                   onclick="return confirm('This will wipe stored iCal history for this calendar. Past dates will only reappear if they are still present in the live iCal feed. Continue?');"
                                   style="display:inline-block; margin-top:8px; color:#d63638; font-size:12px;">
                                   ⚠ Purge stored iCal history
                                </a>
                            </div>
                            <button type="button" class="button cbc-remove-calendar" style="color: #d63638; border-color: #d63638;">Delete Calendar</button>
                        </div>
                        <h4>Rooms in this Calendar:</h4>
                        <div class="cbc-rooms-container" data-cal-id="<?php echo esc_attr($cal_id); ?>">
                            <?php
                            $rooms = isset($calendar['rooms']) ? $calendar['rooms'] : array();
                            foreach ($rooms as $room_id => $room):
                                ?>
                                <div class="cbc-room-block" style="background: #f6f7f7; border: 1px solid #dcdcde; padding: 15px; margin-bottom: 10px; position: relative;">
                                    <button type="button" class="button cbc-remove-room button-small" style="position: absolute; top: 15px; right: 15px;">Remove Room</button>
                                    <table style="width: 100%; max-width: 800px;">
                                        <tr>
                                            <td style="padding: 5px;"><strong>Room Name</strong><br><input type="text" name="cbc_calendars[<?php echo esc_attr($cal_id); ?>][rooms][<?php echo esc_attr($room_id); ?>][name]" value="<?php echo esc_attr(isset($room['name']) ? $room['name'] : ''); ?>" style="width:100%;"></td>
                                            <td style="padding: 5px;"><strong>Color</strong><br><input type="color" name="cbc_calendars[<?php echo esc_attr($cal_id); ?>][rooms][<?php echo esc_attr($room_id); ?>][color]" value="<?php echo esc_attr(isset($room['color']) ? $room['color'] : '#3498db'); ?>"></td>
                                            <td style="padding: 5px;"><strong>Fluent Form ID</strong><br><input type="number" name="cbc_calendars[<?php echo esc_attr($cal_id); ?>][rooms][<?php echo esc_attr($room_id); ?>][form_id]" value="<?php echo esc_attr(isset($room['form_id']) ? $room['form_id'] : ''); ?>" style="width:100%;" placeholder="e.g. 3"></td>
                                        </tr>
                                        <tr>
                                            <td colspan="3" style="padding: 5px;">
                                                <table style="width:100%; border-collapse:separate; border-spacing:0 8px;">
                                                    <tr>
                                                        <td style="padding:6px 10px; background:#e8f4fd; border-left:4px solid #2980b9; border-radius:4px 0 0 4px;">
                                                            <strong style="color:#1a5276;">🏠 Main Listing ID</strong>
                                                            <div style="font-size:11px; color:#555; margin-bottom:4px;">Primary PriceLabs listing (parent)</div>
                                                            <div style="display:flex; gap:8px; align-items:center;">
                                                                <input type="text" id="pricelabs-id-<?php echo esc_attr($room_id); ?>" name="cbc_calendars[<?php echo esc_attr($cal_id); ?>][rooms][<?php echo esc_attr($room_id); ?>][pricelabs]" value="<?php echo esc_attr(isset($room['pricelabs']) ? $room['pricelabs'] : ''); ?>" style="flex:1;" placeholder="e.g. 1634256467359996233">
                                                                <button type="button" class="button cbc-test-pricelabs" data-room-id="<?php echo esc_attr($room_id); ?>">🔍 Test</button>
                                                            </div>
                                                            <span class="cbc-test-result-<?php echo esc_attr($room_id); ?>" style="display:none; margin-top:4px; font-style:italic; font-size:12px;"></span>
                                                        </td>
                                                    </tr>
                                                    <tr>
                                                        <td style="padding:6px 10px; background:#fef9e7; border-left:4px solid #f39c12; border-radius:4px 0 0 4px;">
                                                            <strong style="color:#7d6608;">👶 Child Listing ID</strong>
                                                            <div style="font-size:11px; color:#555; margin-bottom:4px;">Child/secondary PriceLabs listing (optional)</div>
                                                            <div style="display:flex; gap:8px; align-items:center;">
                                                                <input type="text" id="pricelabs-child-id-<?php echo esc_attr($room_id); ?>" name="cbc_calendars[<?php echo esc_attr($cal_id); ?>][rooms][<?php echo esc_attr($room_id); ?>][pricelabs_child]" value="<?php echo esc_attr(isset($room['pricelabs_child']) ? $room['pricelabs_child'] : ''); ?>" style="flex:1;" placeholder="e.g. 9876543210123456789">
                                                                <button type="button" class="button cbc-test-pricelabs" data-room-id="<?php echo esc_attr($room_id); ?>-child" data-input-id="pricelabs-child-id-<?php echo esc_attr($room_id); ?>">🔍 Test</button>
                                                            </div>
                                                            <span class="cbc-test-result-<?php echo esc_attr($room_id); ?>-child" style="display:none; margin-top:4px; font-style:italic; font-size:12px;"></span>
                                                        </td>
                                                    </tr>
                                                </table>
                                            </td>
                                        </tr>
                                    </table>
                                </div>
                            <?php endforeach; ?>
                        </div>
                        <button type="button" class="button button-secondary cbc-add-room" data-cal-id="<?php echo esc_attr($cal_id); ?>">+ Add Room to this Calendar</button>
                    </div>
                <?php endforeach; ?>
            </div>

            <div style="margin-top: 30px;">
                <?php submit_button('Save All Settings'); ?>
            </div>
        </form>

        <script>
            var cbcAdminData = {
                ajaxurl: '<?php echo esc_js(admin_url('admin-ajax.php')); ?>',
                nonce:   '<?php echo esc_js(wp_create_nonce('cbc_nonce')); ?>'
            };
            document.addEventListener('DOMContentLoaded', function () {
                const container = document.getElementById('cbc-calendars-container');

                document.getElementById('cbc-add-calendar').addEventListener('click', function () {
                    const calId = 'cal_' + Date.now();
                    const html = `
                    <div class="cbc-calendar-block" style="background: #fff; border: 1px solid #c3c4c7; padding: 20px; margin-top: 20px; border-radius: 4px; box-shadow: 0 1px 1px rgba(0,0,0,.04);">
                        <div style="display: flex; justify-content: space-between; border-bottom: 1px solid #eee; padding-bottom: 15px; margin-bottom: 15px;">
                            <div>
                                <strong>Calendar Name:</strong> <input type="text" name="cbc_calendars[${calId}][name]" value="New Calendar" class="regular-text">
                                <br><span class="description" style="display:inline-block; margin-top:8px;">Shortcode: <code style="font-size:14px;">[custom_booking_calendar id="${calId}"]</code></span>
                            </div>
                            <button type="button" class="button cbc-remove-calendar" style="color: #d63638; border-color: #d63638;">Delete Calendar</button>
                        </div>
                        <h4>Rooms in this Calendar:</h4>
                        <div class="cbc-rooms-container" data-cal-id="${calId}"></div>
                        <button type="button" class="button button-secondary cbc-add-room" data-cal-id="${calId}">+ Add Room to this Calendar</button>
                    </div>`;
                    container.insertAdjacentHTML('beforeend', html);
                });

                container.addEventListener('click', function (e) {
                    if (e.target.classList.contains('cbc-remove-calendar')) {
                        if (confirm('Delete this entire calendar and its rooms?')) {
                            e.target.closest('.cbc-calendar-block').remove();
                        }
                    }
                    if (e.target.classList.contains('cbc-remove-room')) {
                        if (confirm('Remove this room?')) {
                            e.target.closest('.cbc-room-block').remove();
                        }
                    }
                    if (e.target.classList.contains('cbc-add-room')) {
                        const calId = e.target.getAttribute('data-cal-id');
                        const roomId = 'room_' + Date.now();
                        const roomsContainer = e.target.previousElementSibling;
                        const html = `
                        <div class="cbc-room-block" style="background: #f6f7f7; border: 1px solid #dcdcde; padding: 15px; margin-bottom: 10px; position: relative;">
                            <button type="button" class="button cbc-remove-room button-small" style="position: absolute; top: 15px; right: 15px;">Remove Room</button>
                            <table style="width: 100%; max-width: 800px;">
                                <tr>
                                    <td style="padding: 5px;"><strong>Room Name</strong><br><input type="text" name="cbc_calendars[${calId}][rooms][${roomId}][name]" style="width:100%;"></td>
                                    <td style="padding: 5px;"><strong>Color</strong><br><input type="color" name="cbc_calendars[${calId}][rooms][${roomId}][color]" value="#3498db"></td>
                                    <td style="padding: 5px;"><strong>Fluent Form ID</strong><br><input type="number" name="cbc_calendars[${calId}][rooms][${roomId}][form_id]" style="width:100%;" placeholder="e.g. 3"></td>
                                </tr>
                                <tr><td colspan="3" style="padding: 5px;">
                                    <table style="width:100%; border-collapse:separate; border-spacing:0 8px;">
                                        <tr>
                                            <td style="padding:6px 10px; background:#e8f4fd; border-left:4px solid #2980b9; border-radius:4px 0 0 4px;">
                                                <strong style="color:#1a5276;">🏠 Main Listing ID</strong>
                                                <div style="font-size:11px; color:#555; margin-bottom:4px;">Primary PriceLabs listing (parent)</div>
                                                <div style="display:flex; gap:8px; align-items:center;">
                                                    <input type="text" id="pricelabs-id-${roomId}" name="cbc_calendars[${calId}][rooms][${roomId}][pricelabs]" style="flex:1;" placeholder="e.g. 1634256467359996233">
                                                    <button type="button" class="button cbc-test-pricelabs" data-room-id="${roomId}">🔍 Test</button>
                                                </div>
                                                <span class="cbc-test-result-${roomId}" style="display:none; margin-top:4px; font-style:italic; font-size:12px;"></span>
                                            </td>
                                        </tr>
                                        <tr>
                                            <td style="padding:6px 10px; background:#fef9e7; border-left:4px solid #f39c12; border-radius:4px 0 0 4px;">
                                                <strong style="color:#7d6608;">👶 Child Listing ID</strong>
                                                <div style="font-size:11px; color:#555; margin-bottom:4px;">Child/secondary PriceLabs listing (optional)</div>
                                                <div style="display:flex; gap:8px; align-items:center;">
                                                    <input type="text" id="pricelabs-child-id-${roomId}" name="cbc_calendars[${calId}][rooms][${roomId}][pricelabs_child]" style="flex:1;" placeholder="e.g. 9876543210123456789">
                                                    <button type="button" class="button cbc-test-pricelabs" data-room-id="${roomId}-child" data-input-id="pricelabs-child-id-${roomId}">🔍 Test</button>
                                                </div>
                                                <span class="cbc-test-result-${roomId}-child" style="display:none; margin-top:4px; font-style:italic; font-size:12px;"></span>
                                            </td>
                                        </tr>
                                    </table>
                                </td></tr>
                            </table>
                        </div>`;
                        roomsContainer.insertAdjacentHTML('beforeend', html);
                    }
                });

                // ── Test PriceLabs Connection button handler ──
                document.addEventListener('click', function(e) {
                    if (!e.target.classList.contains('cbc-test-pricelabs')) return;
                    var roomId   = e.target.getAttribute('data-room-id');
                    var inputId  = e.target.getAttribute('data-input-id') || ('pricelabs-id-' + roomId);
                    var input    = document.getElementById(inputId);
                    var span     = document.querySelector('.cbc-test-result-' + roomId);
                    if (!input || !span) return;

                    var listingId = input.value.trim();
                    if (!listingId) { span.style.display='inline'; span.style.color='#c00'; span.textContent='Please enter a Listing ID first.'; return; }

                    span.style.display = 'inline';
                    span.style.color   = '#555';
                    span.textContent   = 'Testing…';
                    e.target.disabled  = true;

                    var fd = new FormData();
                    fd.append('action',     'cbc_test_pricelabs');
                    fd.append('nonce',      cbcAdminData.nonce);
                    fd.append('listing_id', listingId);

                    fetch(cbcAdminData.ajaxurl, { method: 'POST', body: fd })
                        .then(function(r){ return r.json(); })
                        .then(function(r){
                            span.style.color   = r.success ? 'green' : '#c00';
                            span.textContent   = r.success ? r.data : r.data;
                        })
                        .catch(function(){ span.style.color='#c00'; span.textContent='Network error.'; })
                        .finally(function(){ e.target.disabled = false; });
                });
            });
        </script>

        <hr style="margin:40px 0; border-top: 1px solid #c3c4c7;">
        <h2>Manual Booking Entry</h2>
        <p>If you want to manually insert a missing or historical PriceLabs booking directly into the database, you can do so here.</p>
        <form method="post" action="" style="background: #fff; border: 1px solid #c3c4c7; padding: 20px; border-radius: 4px; max-width: 600px;">
            <?php wp_nonce_field('cbc_manual_action', 'cbc_manual_nonce'); ?>
            <input type="hidden" name="cbc_manual_insert" value="1">
            <table class="form-table">
                <tr>
                    <th scope="row"><label>Calendar</label></th>
                    <td>
                        <select name="manual_cal_id" id="manual_cal_id" required style="width: 100%;">
                            <option value="">Select Calendar...</option>
                            <?php foreach ($calendars as $cid => $cal): ?>
                                <option value="<?php echo esc_attr($cid); ?>"><?php echo esc_html($cal['name']); ?></option>
                            <?php endforeach; ?>
                        </select>
                    </td>
                </tr>
                <tr>
                    <th scope="row"><label>Room</label></th>
                    <td>
                        <select name="manual_room_id" id="manual_room_id" required style="width: 100%;">
                            <option value="">Select Room...</option>
                        </select>
                        <script>
                            var cbcRoomsMap = <?php 
                                $map = array();
                                foreach ($calendars as $cid => $cal) {
                                    $map[$cid] = array();
                                    if (!empty($cal['rooms'])) {
                                        foreach ($cal['rooms'] as $rid => $r) {
                                            $map[$cid][] = array('id' => $rid, 'name' => $r['name']);
                                        }
                                    }
                                }
                                echo wp_json_encode($map);
                            ?>;
                            document.getElementById('manual_cal_id').addEventListener('change', function() {
                                var roomSelect = document.getElementById('manual_room_id');
                                roomSelect.innerHTML = '<option value="">Select Room...</option>';
                                var rooms = cbcRoomsMap[this.value] || [];
                                rooms.forEach(function(r) {
                                    var opt = document.createElement('option');
                                    opt.value = r.id;
                                    opt.textContent = r.name;
                                    roomSelect.appendChild(opt);
                                });
                            });
                        </script>
                    </td>
                </tr>
                <tr>
                    <th scope="row"><label>Check-in Date</label></th>
                    <td><input type="date" name="manual_start" required style="width: 100%;"></td>
                </tr>
                <tr>
                    <th scope="row"><label>Check-out Date</label></th>
                    <td><input type="date" name="manual_end" required style="width: 100%;"></td>
                </tr>
                <tr>
                    <th scope="row"><label>Status</label></th>
                    <td>
                        <select name="manual_status" style="width: 100%;">
                            <option value="active">Active (Show on Calendar)</option>
                            <option value="cancelled">Cancelled (Hide from Calendar)</option>
                        </select>
                    </td>
                </tr>
            </table>
            <div style="margin-top: 15px;">
                <?php submit_button('Insert Manual Booking', 'secondary', 'submit', false); ?>
            </div>
        </form>
    </div>
<?php
}

function cbc_render_bookings_data_page()
{
    if (!current_user_can('manage_options')) return;
    global $wpdb;
    $db_table = $wpdb->prefix . 'cbc_pricelabs_bookings_data';

    // Handle Edit / Delete Actions
    if (isset($_POST['cbc_action']) && check_admin_referer('cbc_data_action', 'cbc_data_nonce')) {
        $action = sanitize_text_field($_POST['cbc_action']);
        $id     = intval($_POST['booking_id']);
        
        if ($action === 'delete') {
            $wpdb->delete($db_table, array('id' => $id));
            echo '<div class="notice notice-success is-dismissible"><p>Booking deleted successfully.</p></div>';
        } elseif ($action === 'edit') {
            $start_date = sanitize_text_field($_POST['edit_start_date']);
            $end_date   = sanitize_text_field($_POST['edit_end_date']);
            $status     = sanitize_text_field($_POST['edit_status']);
            $nights     = (int)round((strtotime($end_date) - strtotime($start_date)) / 86400);
            
            $wpdb->update(
                $db_table,
                array(
                    'start_date' => $start_date,
                    'end_date'   => $end_date,
                    'status'     => $status,
                    'nights'     => $nights
                ),
                array('id' => $id)
            );
            // Clear all calendar transients since data changed
            $calendars = get_option('cbc_calendars', array());
            foreach ($calendars as $cal_id => $cal) {
                delete_transient('cbc_events_' . $cal_id);
            }
            echo '<div class="notice notice-success is-dismissible"><p>Booking updated successfully.</p></div>';
        }
    }

    // Pagination & Filtering
    $paged = isset($_GET['paged']) ? max(1, intval($_GET['paged'])) : 1;
    $per_page = 50;
    
    $where = array("1=1");
    if (!empty($_GET['s'])) {
        $s = '%' . $wpdb->esc_like(sanitize_text_field($_GET['s'])) . '%';
        $where[] = $wpdb->prepare("(room_name LIKE %s OR start_date LIKE %s OR end_date LIKE %s OR platform LIKE %s)", $s, $s, $s, $s);
    }
    if (!empty($_GET['filter_room'])) {
        $where[] = $wpdb->prepare("room_name = %s", sanitize_text_field($_GET['filter_room']));
    }
    if (!empty($_GET['filter_status'])) {
        $where[] = $wpdb->prepare("status = %s", sanitize_text_field($_GET['filter_status']));
    }

    $where_sql = implode(' AND ', $where);
    $total_items = $wpdb->get_var("SELECT COUNT(*) FROM `$db_table` WHERE $where_sql");
    $total_pages = ceil($total_items / $per_page);
    $offset = ($paged - 1) * $per_page;

    $results = $wpdb->get_results("SELECT * FROM `$db_table` WHERE $where_sql ORDER BY start_date DESC LIMIT $offset, $per_page");

    // Fetch distinct rooms for filter dropdown
    $distinct_rooms = $wpdb->get_col("SELECT DISTINCT room_name FROM `$db_table` WHERE room_name != ''");
?>
    <div class="wrap">
        <h1 class="wp-heading-inline">All Bookings Data</h1>
        <hr class="wp-header-end">

        <form method="GET" style="margin-bottom: 20px;">
            <input type="hidden" name="page" value="cbc-bookings-data">
            <input type="search" name="s" value="<?php echo esc_attr(isset($_GET['s']) ? $_GET['s'] : ''); ?>" placeholder="Search bookings..." style="margin-right: 5px;">
            <select name="filter_room">
                <option value="">All Rooms</option>
                <?php foreach ($distinct_rooms as $dr): ?>
                    <option value="<?php echo esc_attr($dr); ?>" <?php selected(isset($_GET['filter_room']) ? $_GET['filter_room'] : '', $dr); ?>><?php echo esc_html($dr); ?></option>
                <?php endforeach; ?>
            </select>
            
            <select name="filter_status">
                <option value="">All Statuses</option>
                <option value="active" <?php selected(isset($_GET['filter_status']) ? $_GET['filter_status'] : '', 'active'); ?>>Active</option>
                <option value="cancelled" <?php selected(isset($_GET['filter_status']) ? $_GET['filter_status'] : '', 'cancelled'); ?>>Cancelled</option>
            </select>

            <?php submit_button('Filter', 'button', '', false); ?>
            <a href="?page=cbc-bookings-data" class="button">Clear</a>
        </form>

        <table class="wp-list-table widefat fixed striped table-view-list">
            <thead>
                <tr>
                    <th style="width: 50px;">ID</th>
                    <th>Room Name</th>
                    <th>Check-in</th>
                    <th>Check-out</th>
                    <th>Nights</th>
                    <th>Platform</th>
                    <th>Status</th>
                    <th>Actions</th>
                </tr>
            </thead>
            <tbody>
                <?php if (empty($results)): ?>
                    <tr><td colspan="8">No bookings found.</td></tr>
                <?php else: ?>
                    <?php foreach ($results as $row): ?>
                        <tr>
                            <td><?php echo (int)$row->id; ?></td>
                            <td><strong><?php echo esc_html($row->room_name); ?></strong></td>
                            <td><?php echo esc_html($row->start_date); ?></td>
                            <td><?php echo esc_html($row->end_date); ?></td>
                            <td><?php echo (int)$row->nights; ?></td>
                            <td><?php echo esc_html($row->platform); ?></td>
                            <td>
                                <?php if ($row->status === 'active'): ?>
                                    <span style="color: green; font-weight: bold;">Active</span>
                                <?php else: ?>
                                    <span style="color: #d63638; font-weight: bold;">Cancelled</span>
                                <?php endif; ?>
                            </td>
                            <td>
                                <button type="button" class="button button-small cbc-edit-btn" 
                                    data-id="<?php echo (int)$row->id; ?>"
                                    data-start="<?php echo esc_attr($row->start_date); ?>"
                                    data-end="<?php echo esc_attr($row->end_date); ?>"
                                    data-status="<?php echo esc_attr($row->status); ?>">Edit</button>
                                
                                <form method="POST" style="display:inline-block;" onsubmit="return confirm('Are you sure you want to delete this booking permanently?');">
                                    <?php wp_nonce_field('cbc_data_action', 'cbc_data_nonce'); ?>
                                    <input type="hidden" name="cbc_action" value="delete">
                                    <input type="hidden" name="booking_id" value="<?php echo (int)$row->id; ?>">
                                    <button type="submit" class="button button-small" style="color:#d63638; border-color:#d63638;">Delete</button>
                                </form>
                            </td>
                        </tr>
                    <?php endforeach; ?>
                <?php endif; ?>
            </tbody>
        </table>

        <?php if ($total_pages > 1): ?>
            <div class="tablenav bottom">
                <div class="tablenav-pages">
                    <span class="displaying-num"><?php echo $total_items; ?> items</span>
                    <span class="pagination-links">
                        <?php for ($i = 1; $i <= $total_pages; $i++): ?>
                            <a class="button <?php echo ($i === $paged) ? 'active' : ''; ?>" href="?page=cbc-bookings-data&paged=<?php echo $i; ?>&filter_room=<?php echo esc_attr(isset($_GET['filter_room']) ? $_GET['filter_room'] : ''); ?>&filter_status=<?php echo esc_attr(isset($_GET['filter_status']) ? $_GET['filter_status'] : ''); ?>"><?php echo $i; ?></a>
                        <?php endfor; ?>
                    </span>
                </div>
            </div>
        <?php endif; ?>

        <!-- Edit Dialog -->
        <dialog id="cbc-edit-dialog" style="padding: 20px; border: 1px solid #ccc; border-radius: 4px; box-shadow: 0 4px 8px rgba(0,0,0,0.1); width: 300px;">
            <h3 style="margin-top:0;">Edit Booking</h3>
            <form method="POST">
                <?php wp_nonce_field('cbc_data_action', 'cbc_data_nonce'); ?>
                <input type="hidden" name="cbc_action" value="edit">
                <input type="hidden" name="booking_id" id="edit-booking-id" value="">
                
                <p>
                    <label>Check-in Date:</label><br>
                    <input type="date" name="edit_start_date" id="edit-start-date" required style="width:100%;">
                </p>
                <p>
                    <label>Check-out Date:</label><br>
                    <input type="date" name="edit_end_date" id="edit-end-date" required style="width:100%;">
                </p>
                <p>
                    <label>Status:</label><br>
                    <select name="edit_status" id="edit-status" style="width:100%;">
                        <option value="active">Active</option>
                        <option value="cancelled">Cancelled</option>
                    </select>
                </p>
                <div style="display:flex; justify-content:flex-end; gap:10px; margin-top:20px;">
                    <button type="button" class="button" onclick="document.getElementById('cbc-edit-dialog').close();">Cancel</button>
                    <button type="submit" class="button button-primary">Save Changes</button>
                </div>
            </form>
        </dialog>

        <script>
            document.addEventListener('DOMContentLoaded', function() {
                const dialog = document.getElementById('cbc-edit-dialog');
                document.querySelectorAll('.cbc-edit-btn').forEach(btn => {
                    btn.addEventListener('click', function() {
                        document.getElementById('edit-booking-id').value = this.dataset.id;
                        document.getElementById('edit-start-date').value = this.dataset.start;
                        document.getElementById('edit-end-date').value   = this.dataset.end;
                        document.getElementById('edit-status').value     = this.dataset.status;
                        dialog.showModal();
                    });
                });
            });
        </script>
    </div>
<?php
}

// ══════════════════════════════════════════════════════════════════
// SECTION 2 — ENQUEUE SCRIPTS & STYLES
// ══════════════════════════════════════════════════════════════════
add_action('wp_enqueue_scripts', 'cbc_enqueue_calendar_scripts');
function cbc_enqueue_calendar_scripts()
{
    wp_enqueue_style('fullcalendar-css', 'https://cdn.jsdelivr.net/npm/fullcalendar@5.11.3/main.min.css');
    wp_enqueue_script('fullcalendar-js', 'https://cdn.jsdelivr.net/npm/fullcalendar@5.11.3/main.min.js', array(), null, true);
}

// ══════════════════════════════════════════════════════════════════
// SECTION 3 — AJAX REFRESH + TEST ENDPOINTS
// ══════════════════════════════════════════════════════════════════
add_action('wp_ajax_cbc_test_pricelabs', 'cbc_ajax_test_pricelabs');
function cbc_ajax_test_pricelabs()
{
    check_ajax_referer('cbc_nonce', 'nonce');
    if (!current_user_can('manage_options'))
        wp_send_json_error('Unauthorized');

    $listing_id = isset($_POST['listing_id']) ? sanitize_text_field($_POST['listing_id']) : '';
    if (empty($listing_id))
        wp_send_json_error('No listing ID provided');

    $pl_api_key = get_option('cbc_pricelabs_api_key', '');
    if (empty($pl_api_key)) {
        $pl_api_key = 'VntcsoXUUV4r1fRzMBXByv0yQ15AP8o2WzlwTfVH';
    }
    $pl_headers = array(
        'X-API-Key'    => $pl_api_key,
        'Content-Type' => 'application/json',
    );

    // Step 1: Fetch listings to confirm listing ID exists and get pms
    $listings_resp = wp_remote_get('https://api.pricelabs.co/v1/listings', array(
        'timeout' => 15,
        'headers' => $pl_headers,
    ));

    if (is_wp_error($listings_resp)) {
        wp_send_json_error('❌ Could not reach PriceLabs API: ' . $listings_resp->get_error_message());
    }
    $listings_code = wp_remote_retrieve_response_code($listings_resp);
    if ($listings_code != 200) {
        wp_send_json_error('❌ PriceLabs listings API returned HTTP ' . $listings_code . '. Check your API key.');
    }

    $listings_data = json_decode(wp_remote_retrieve_body($listings_resp), true);
    $found_listing = null;
    $pms           = 'airbnb';
    if (!empty($listings_data['listings'])) {
        foreach ($listings_data['listings'] as $lst) {
            if ((string)$lst['id'] === (string)$listing_id) {
                $found_listing = $lst;
                $pms = $lst['pms'];
                break;
            }
        }
    }
    if (!$found_listing) {
        wp_send_json_error('⚠️ PriceLabs API is reachable, but Listing ID "' . esc_html($listing_id) . '" was not found in your account. Total listings: ' . count($listings_data['listings'] ?? []));
    }

    // Step 2: Fetch calendar to count booked days
    $prices_resp = wp_remote_post('https://api.pricelabs.co/v1/listing_prices', array(
        'timeout' => 20,
        'headers' => $pl_headers,
        'body'    => wp_json_encode(array('listings' => array(array('id' => $listing_id, 'pms' => $pms)))),
    ));

    if (is_wp_error($prices_resp)) {
        wp_send_json_error('❌ Could not fetch calendar from PriceLabs: ' . $prices_resp->get_error_message());
    }
    $prices_code = wp_remote_retrieve_response_code($prices_resp);
    if ($prices_code != 200) {
        wp_send_json_error('❌ PriceLabs listing_prices API returned HTTP ' . $prices_code);
    }

    $calendar = json_decode(wp_remote_retrieve_body($prices_resp), true);
    $booked   = 0;
    if (!empty($calendar[0]['data'])) {
        foreach ($calendar[0]['data'] as $d) {
            if (in_array($d['booking_status'] ?? '', array('Booked', 'Booked (Check-In)'))) $booked++;
        }
    }

    wp_send_json_success('✅ Connected! Listing: "' . esc_html($found_listing['name'] ?? $listing_id) . '" (PMS: ' . esc_html($pms) . ') — ' . $booked . ' booked day(s) found in calendar.');
}

add_action('wp_ajax_cbc_refresh', 'cbc_ajax_refresh');
add_action('wp_ajax_nopriv_cbc_refresh', 'cbc_ajax_refresh');
function cbc_ajax_refresh()
{
    check_ajax_referer('cbc_nonce', 'nonce');
    $cal_id = isset($_POST['cal_id']) ? sanitize_text_field($_POST['cal_id']) : '';
    if (!$cal_id)
        wp_send_json_error('No calendar ID provided');
    delete_transient('cbc_events_' . $cal_id);
    $events = cbc_get_merged_events($cal_id);
    wp_send_json_success(array(
        'events'      => $events,
        'last_synced' => current_time('d M Y, H:i'),
    ));
}

// ══════════════════════════════════════════════════════════════════
// SECTION 4 — HELPERS
// ══════════════════════════════════════════════════════════════════
function cbc_tint_color($hex, $factor = 0.55)
{
    $hex = ltrim($hex, '#');
    $r = hexdec(substr($hex, 0, 2));
    $g = hexdec(substr($hex, 2, 2));
    $b = hexdec(substr($hex, 4, 2));
    return sprintf('#%02x%02x%02x', (int)round($r + (255 - $r) * $factor), (int)round($g + (255 - $g) * $factor), (int)round($b + (255 - $b) * $factor));
}

function cbc_parse_ical($data)
{
    $slots = array();
    preg_match_all('/BEGIN:VEVENT.*?END:VEVENT/s', $data, $m);
    if (empty($m[0]))
        return $slots;
    foreach ($m[0] as $block) {
        preg_match('/DTSTART(?:;.*?)?:([0-9A-Z]+)/', $block, $s);
        preg_match('/DTEND(?:;.*?)?:([0-9A-Z]+)/', $block, $e);
        preg_match('/SUMMARY[^:]*:(.+)/i', $block, $sum);
        preg_match('/UID[^:]*:(.+)/i', $block, $uid);
        if (empty($s[1]) || empty($e[1]))
            continue;
        $slots[] = array(
            'start'   => date('Y-m-d', strtotime($s[1])),
            'end'     => date('Y-m-d', strtotime($e[1])),
            'summary' => isset($sum[1]) ? trim($sum[1]) : '',
            'uid'     => isset($uid[1]) ? trim($uid[1]) : '',
        );
    }
    return $slots;
}

function cbc_is_echo($summary, $platform)
{
    $s = strtolower($summary);
    if ($platform === 'airbnb' && strpos($s, 'booking') !== false)
        return true;
    if ($platform === 'booking' && strpos($s, 'airbnb') !== false)
        return true;
    return false;
}

function cbc_is_blocked($summary)
{
    $s = trim(strtolower($summary));
    if ($s === 'not available' || $s === 'closed' || $s === 'blocked' || $s === 'airbnb (not available)')
        return true;
    return false;
}

function cbc_is_room_match($submitted_room, $plugin_room_name, $form_id, $rooms_array)
{
    if (empty($submitted_room)) return true;
    $s = trim(strtolower($submitted_room));
    $p = trim(strtolower($plugin_room_name));
    
    $form_id_count = 0;
    foreach ($rooms_array as $r) {
        if (isset($r['form_id']) && intval($r['form_id']) == $form_id) $form_id_count++;
    }
    if ($form_id_count == 1) return true;
    
    if (strpos($s, $p) !== false || strpos($p, $s) !== false) return true;
    
    $map = array(
        'room 1' => 'room 1 eyre square',
        'room 2' => 'room 2 eyre square',
        'room 3' => 'room 3 eyre square',
        'room 4' => 'room 4 eyre square',
        'room 5' => 'room 5 eyre square',
        '18 kirwans court' => 'kirwans lane',
        'kirwans lane' => '18 kirwans court'
    );
    foreach ($map as $k => $v) {
        if ((strpos($s, $k) !== false && strpos($p, $v) !== false) ||
            (strpos($s, $v) !== false && strpos($p, $k) !== false)) {
            return true;
        }
    }
    return false;
}

// ── NEW: persistent iCal storage helpers ──────────────────────────
function cbc_get_stored_ical($cal_id)
{
    $stored = get_option('cbc_stored_ical_' . $cal_id, array());
    return is_array($stored) ? $stored : array();
}

function cbc_save_stored_ical($cal_id, $stored)
{
    // Use autoload=false because this option can grow large over time.
    update_option('cbc_stored_ical_' . $cal_id, $stored, false);
}

function cbc_setup_database_table() {
    global $wpdb;
    $table_name = $wpdb->prefix . 'cbc_pricelabs_bookings_data';
    $charset_collate = $wpdb->get_charset_collate();

    $sql = "CREATE TABLE $table_name (
        id bigint(20) unsigned NOT NULL AUTO_INCREMENT,
        cal_id varchar(100) NOT NULL,
        room_id varchar(100) NOT NULL,
        room_name varchar(150) DEFAULT '' NOT NULL,
        platform varchar(50) NOT NULL,
        start_date date NOT NULL,
        end_date date NOT NULL,
        summary varchar(255) DEFAULT '' NOT NULL,
        uid varchar(150) NOT NULL,
        nights int(11) DEFAULT NULL,
        booked_on varchar(100) DEFAULT '' NOT NULL,
        status varchar(20) DEFAULT 'active' NOT NULL,
        is_blocked tinyint(1) DEFAULT 0 NOT NULL,
        form_data longtext DEFAULT NULL,
        last_seen datetime DEFAULT '0000-00-00 00:00:00' NOT NULL,
        PRIMARY KEY  (id),
        UNIQUE KEY booking_uid (uid)
    ) $charset_collate;";

    require_once( ABSPATH . 'wp-admin/includes/upgrade.php' );
    dbDelta( $sql );
}
add_action('admin_init', 'cbc_setup_database_table');

/**
 * Delete all Fluent Forms submissions matching a check-in date and room.
 * Called when an iCal event disappears from the feed (= cancellation).
 *
 * Returns the number of submissions deleted.
 */
function cbc_delete_fluent_form_entries_for_booking($form_id, $checkin_date, $room_name)
{
    // Completely disabled. This plugin will never delete or trash any Fluent Form entries.
    return 0;
}

// ══════════════════════════════════════════════════════════════════
// SECTION 5 — CORE DATA FETCHING & MERGING (with persistence + cancellation cleanup)
// ══════════════════════════════════════════════════════════════════
function cbc_get_merged_events($cal_id)
{
    global $wpdb;

    // Safety check: ensure room_name column exists (in case dbDelta failed)
    $db_table = $wpdb->prefix . 'cbc_pricelabs_bookings_data';
    if ($wpdb->get_var("SHOW TABLES LIKE '$db_table'") == $db_table) {
        $col = $wpdb->get_results("SHOW COLUMNS FROM `$db_table` LIKE 'room_name'");
        if (empty($col)) {
            $wpdb->query("ALTER TABLE `$db_table` ADD `room_name` varchar(150) DEFAULT '' NOT NULL AFTER `room_id`");
        }
    }

    $cached = get_transient('cbc_events_' . $cal_id);
    if (false !== $cached)
        return $cached;

    $calendars = get_option('cbc_calendars', array());
    if (!isset($calendars[$cal_id]) || empty($calendars[$cal_id]['rooms']))
        return array();

    $rooms  = $calendars[$cal_id]['rooms'];
    $result = array();

    $ff_table  = $wpdb->prefix . 'fluentform_submissions';
    $ff_exists = ($wpdb->get_var("SHOW TABLES LIKE '$ff_table'") == $ff_table);

    // Load the persistent iCal store once for this calendar.
    $stored_all = cbc_get_stored_ical($cal_id);
    $today      = date('Y-m-d');

    foreach ($rooms as $room_id => $room) {
        $room_name = isset($room['name']) ? $room['name'] : 'Unknown';
        $base      = isset($room['color']) ? $room['color'] : '#333333';
        $form_id   = isset($room['form_id']) ? intval($room['form_id']) : 0;

        // ── 1. Fetch fresh data directly from PriceLabs API ──────────────────
        $raw            = array('pricelabs' => array());
        $fetch_success  = array('pricelabs' => false);
        
        $pl_ids = array();
        if (!empty($room['pricelabs'])) $pl_ids[] = trim($room['pricelabs']);
        if (!empty($room['pricelabs_child'])) $pl_ids[] = trim($room['pricelabs_child']);

        if (!empty($pl_ids)) {
            $pl_api_key = get_option('cbc_pricelabs_api_key', '');
            if (empty($pl_api_key)) {
                $pl_api_key = 'VntcsoXUUV4r1fRzMBXByv0yQ15AP8o2WzlwTfVH'; // fallback default
            }
            $pl_headers = array(
                'X-API-Key'    => $pl_api_key,
                'Content-Type' => 'application/json',
            );

            // Set up fetch map with 'airbnb' as sensible default
            $listings_to_fetch = array();
            foreach ($pl_ids as $pid) {
                $listings_to_fetch[$pid] = array('id' => $pid, 'pms' => 'airbnb');
            }

            // Step 1: Get listings to find pms for these listing_ids
            $listings_resp = wp_remote_get('https://api.pricelabs.co/v1/listings', array(
                'timeout' => 20,
                'headers' => $pl_headers,
            ));

            if (!is_wp_error($listings_resp) && wp_remote_retrieve_response_code($listings_resp) == 200) {
                $listings_body = json_decode(wp_remote_retrieve_body($listings_resp), true);
                if (!empty($listings_body['listings'])) {
                    foreach ($listings_body['listings'] as $lst) {
                        $pid = (string)$lst['id'];
                        if (isset($listings_to_fetch[$pid])) {
                            $listings_to_fetch[$pid]['pms'] = $lst['pms'];
                        }
                    }
                }
            }

            // Step 2: POST to listing_prices to get the calendar for all listings
            $prices_resp = wp_remote_post('https://api.pricelabs.co/v1/listing_prices', array(
                'timeout' => 30,
                'headers' => $pl_headers,
                'body'    => wp_json_encode(array(
                    'listings' => array_values($listings_to_fetch)
                )),
            ));

            if (!is_wp_error($prices_resp) && wp_remote_retrieve_response_code($prices_resp) == 200) {
                $fetch_success['pricelabs'] = true; // successfully hit API
                $calendar_data = json_decode(wp_remote_retrieve_body($prices_resp), true);
                
                if (!empty($calendar_data) && is_array($calendar_data)) {
                    $all_slots = array();

                    foreach ($calendar_data as $cal_item) {
                        if (empty($cal_item['data'])) continue;
                        $days = $cal_item['data'];
                        $item_id = isset($cal_item['listing_id']) ? $cal_item['listing_id'] : 'unknown'; // Note: API usually returns id or listing_id
                        
                        usort($days, function($a, $b){ return strcmp($a['date'], $b['date']); });

                        // ── Group booked days into reservations ──────────────────────────────
                        $bookings = array();
                        $current  = null;

                        foreach ($days as $day) {
                            $status    = isset($day['booking_status']) ? $day['booking_status'] : '';
                            $date_str  = $day['date'];
                            $booked_on = isset($day['booked_date']) ? $day['booked_date'] : '';
                            $is_checkin = ($status === 'Booked (Check-In)');
                            $is_booked  = ($status === 'Booked' || $is_checkin);

                            if ($is_booked) {
                                $gap = ($current !== null)
                                    ? (strtotime($date_str) - strtotime($current['last'])) / 86400
                                    : 999;

                                $start_new = ($current === null || $is_checkin || $gap > 1);

                                if ($start_new) {
                                    if ($current !== null) {
                                        $checkout   = date('Y-m-d', strtotime($current['last']) + 86400);
                                        $bookings[] = array(
                                            'start'           => $current['start'],
                                            'end'             => $checkout,
                                            'nights'          => (int)round((strtotime($checkout) - strtotime($current['start'])) / 86400),
                                            'booked_on'       => $current['booked_on'],
                                            'is_continuation' => isset($current['is_continuation']) ? $current['is_continuation'] : false,
                                        );
                                    }
                                    $current = array(
                                        'start'           => $date_str,
                                        'last'            => $date_str,
                                        'booked_on'       => $booked_on,
                                        'is_continuation' => (!$is_checkin),
                                    );
                                } else {
                                    $current['last'] = $date_str;
                                }
                            } else {
                                if ($current !== null) {
                                    $checkout   = date('Y-m-d', strtotime($current['last']) + 86400);
                                    $bookings[] = array(
                                        'start'     => $current['start'],
                                        'end'       => $checkout,
                                        'nights'    => (int)round((strtotime($checkout) - strtotime($current['start'])) / 86400),
                                        'booked_on' => $current['booked_on'],
                                    );
                                    $current = null;
                                }
                            }
                        }
                        if ($current !== null) {
                            $checkout   = date('Y-m-d', strtotime($current['last']) + 86400);
                            $bookings[] = array(
                                'start'           => $current['start'],
                                'end'             => $checkout,
                                'nights'          => (int)round((strtotime($checkout) - strtotime($current['start'])) / 86400),
                                'booked_on'       => $current['booked_on'],
                                'is_continuation' => isset($current['is_continuation']) ? $current['is_continuation'] : false,
                            );
                        }

                        if (!empty($bookings)) {
                            foreach ($bookings as $bk) {
                                $all_slots[] = array(
                                    'start'           => $bk['start'],
                                    'end'             => $bk['end'],
                                    'summary'         => 'PriceLabs Booking',
                                    'uid'             => md5($item_id . $bk['start'] . $bk['end']),
                                    'nights'          => $bk['nights'],
                                    'booked_on'       => $bk['booked_on'],
                                    'is_continuation' => isset($bk['is_continuation']) ? $bk['is_continuation'] : false,
                                );
                            }
                        }
                    }
                    $raw['pricelabs'] = $all_slots;
                }
            }
        }


        $clean = array();
        foreach ($raw as $platform => $slots) {
            $clean[$platform] = $slots;
        }

        // ── 2. Merge fresh data with the persistent DB table ──────────
        $db_table = $wpdb->prefix . 'cbc_pricelabs_bookings_data';
        $current_time = current_time('mysql');

        // Migrate from old options array to DB if this room is empty in DB
        $has_db_records = $wpdb->get_var($wpdb->prepare("SELECT COUNT(*) FROM $db_table WHERE cal_id = %s AND room_id = %s", $cal_id, $room_id));
        $stored_for_room = isset($stored_all[$room_id]) && is_array($stored_all[$room_id]) ? $stored_all[$room_id] : array();
        
        if ($has_db_records == 0 && !empty($stored_for_room)) {
            foreach ($stored_for_room as $key => $slot) {
                $p = isset($slot['platform']) ? $slot['platform'] : 'pricelabs';
                $s = isset($slot['start']) ? $slot['start'] : '';
                $e = isset($slot['end']) ? $slot['end'] : '';
                if (empty($s) || empty($e)) continue;
                $t_uid = md5($cal_id . '_' . $room_id . '_' . $p . '_' . $s . '_' . $e);
                $is_b = cbc_is_blocked($slot['summary']) ? 1 : 0;
                $n = isset($slot['nights']) ? $slot['nights'] : 0;
                $b_on = isset($slot['booked_on']) ? $slot['booked_on'] : '';
                
                $wpdb->query($wpdb->prepare(
                    "INSERT IGNORE INTO $db_table (cal_id, room_id, room_name, platform, start_date, end_date, summary, uid, nights, booked_on, status, is_blocked, last_seen) 
                     VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %d, %s, 'active', %d, %s)",
                    $cal_id, $room_id, $room_name, $p, $s, $e, $slot['summary'], $t_uid, $n, $b_on, $is_b, $current_time
                ));
            }
        }

        // 2-Pre. Lock ongoing bookings (Irish Time) & Restore check-in dates cut off by PriceLabs feed.
        $tz = new DateTimeZone('Europe/Dublin');
        $dt = new DateTime("now", $tz);
        $today_str = $dt->format('Y-m-d');
        
        if (!empty($clean['pricelabs'])) {
            $active_db = $wpdb->get_results($wpdb->prepare(
                "SELECT * FROM $db_table WHERE cal_id = %s AND room_id = %s AND platform = 'pricelabs' AND status = 'active'",
                $cal_id, $room_id
            ));
            
            foreach ($clean['pricelabs'] as &$fresh) {
                $best_match = null;
                foreach ($active_db as $stored_event) {
                    // Lock condition: if a DB booking is already ongoing/started, and the new slot falls inside it.
                    if (strtotime($stored_event->start_date) <= strtotime($fresh['start']) && 
                        strtotime($stored_event->end_date) > strtotime($fresh['start'])) {
                        $best_match = $stored_event;
                        break;
                    }
                }
                if ($best_match) {
                    // Restore original check-in date to prevent overriding with a shorter slot
                    $fresh['start']  = $best_match->start_date;
                    $fresh['nights'] = (int)round((strtotime($fresh['end']) - strtotime($fresh['start'])) / 86400);
                    $fresh['uid']    = md5('pricelabs' . $fresh['start'] . $fresh['end']);
                }
            }
            unset($fresh);
        }

        // 2a. Insert or Update fresh events into the database
        foreach (array('pricelabs') as $platform) {
            if (empty($fetch_success[$platform]))
                continue;

            foreach ($clean[$platform] as $slot) {
                $table_uid = md5($cal_id . '_' . $room_id . '_' . $platform . '_' . $slot['start'] . '_' . $slot['end']);
                $is_blocked = cbc_is_blocked($slot['summary']) ? 1 : 0;
                $nights = isset($slot['nights']) ? intval($slot['nights']) : 0;
                $booked_on = isset($slot['booked_on']) ? $slot['booked_on'] : '';
                
                $wpdb->query($wpdb->prepare(
                    "INSERT INTO $db_table (cal_id, room_id, room_name, platform, start_date, end_date, summary, uid, nights, booked_on, status, is_blocked, last_seen) 
                     VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %d, %s, 'active', %d, %s)
                     ON DUPLICATE KEY UPDATE 
                     room_name = VALUES(room_name), summary = VALUES(summary), nights = VALUES(nights), booked_on = VALUES(booked_on), status = 'active', is_blocked = VALUES(is_blocked), last_seen = VALUES(last_seen)",
                    $cal_id, $room_id, $room_name, $platform, $slot['start'], $slot['end'], $slot['summary'], $table_uid, $nights, $booked_on, $is_blocked, $current_time
                ));
            }
        }

        // 2b. Detect cancellations: stored active events that are missing from a *successful* fresh fetch
        foreach (array('pricelabs') as $platform) {
            if (empty($fetch_success[$platform]))
                continue;

            $missing_active = $wpdb->get_results($wpdb->prepare(
                "SELECT id, start_date, end_date FROM $db_table WHERE cal_id = %s AND room_id = %s AND platform = %s AND status = 'active' AND last_seen < %s AND summary != 'Manual Entry'",
                $cal_id, $room_id, $platform, $current_time
            ));
            
            foreach ($missing_active as $missing) {
                // User requested Lock: If booking check-in has started, do not cancel it.
                $is_locked = (strtotime($missing->start_date) <= strtotime($today_str) && strtotime($missing->end_date) > strtotime($today_str));

                // If it's a future stay, it's cancelled. But skip if it's locked (ongoing)
                if (!$is_locked && strtotime($missing->end_date) > strtotime($today_str)) {
                    $wpdb->update(
                        $db_table,
                        array('status' => 'cancelled'),
                        array('id' => $missing->id)
                    );
                }
                // Else it's a past stay, keep as 'active' (history)
            }
        }

        // Fetch the active events from the DB to proceed with Fluent Forms matching and rendering
        $stored_for_room = array();
        $active_from_db = $wpdb->get_results($wpdb->prepare(
            "SELECT * FROM $db_table WHERE cal_id = %s AND room_id = %s AND status = 'active'",
            $cal_id, $room_id
        ), ARRAY_A);
        
        foreach ($active_from_db as $db_row) {
            $key = $db_row['platform'] . '|' . $db_row['start_date'] . '|' . $db_row['end_date'];
            $stored_for_room[$key] = array(
                'platform'  => $db_row['platform'],
                'start'     => $db_row['start_date'],
                'end'       => $db_row['end_date'],
                'summary'   => $db_row['summary'],
                'uid'       => $db_row['uid'],
                'nights'    => $db_row['nights'],
                'booked_on' => $db_row['booked_on'],
            );
        }

        // ── 3. Fetch Fluent Forms submissions (after any cancellation cleanup) ──
        $form_data_entries = array();
        if ($ff_exists && $form_id > 0) {
            // Newest first — so the matching loop prefers the most recent submission.
            $submissions = $wpdb->get_results($wpdb->prepare(
                "SELECT response, created_at FROM $ff_table WHERE form_id = %d AND status != 'trashed' ORDER BY created_at DESC, id DESC",
                $form_id
            ));
            foreach ($submissions as $sub) {
                $raw_resp = json_decode($sub->response, true);
                if (is_array($raw_resp)) {
                    $clean_resp = array();
                    foreach ($raw_resp as $k => $v) {
                        if (strpos($k, '__') === 0)
                            continue; // Skip system fields
                        $display_key = ucwords(str_replace(array('_', '-'), ' ', $k));
                        $clean_resp[$display_key] = is_array($v) ? implode(', ', $v) : $v;
                    }
                    $form_data_entries[] = $clean_resp;
                }
            }
        }

        // ── 4. Build calendar events from the persistent store ─────
        // Deduplicate by start|end so a slot present on both platforms only renders once
        $seen = array();
        $platform_order = array('pricelabs', 'airbnb', 'booking');

        // Group stored events by platform for the same dedup walk order.
        $by_platform = array('pricelabs' => array(), 'airbnb' => array(), 'booking' => array());
        foreach ($stored_for_room as $event) {
            $p = isset($event['platform']) ? $event['platform'] : '';
            if (!isset($by_platform[$p])) {
                $by_platform[$p] = array();
                if (!in_array($p, $platform_order)) {
                    $platform_order[] = $p;
                }
            }
            $by_platform[$p][] = $event;
        }

        foreach ($platform_order as $platform) {
            if (empty($by_platform[$platform])) continue;

            foreach ($by_platform[$platform] as $slot) {
                $key = $slot['start'] . '|' . $slot['end'];
                if (isset($seen[$key]))
                    continue;
                $seen[$key] = 1;

                $is_blocked = cbc_is_blocked($slot['summary']);
                if ($is_blocked) {
                    $bg             = '#cbd5e1';
                    $fg             = '#475569';
                    $event_title    = 'Blocked - ' . $room_name;
                    $platform_label = 'Blocked (' . ucfirst($platform) . ')';
                } else if ($platform === 'pricelabs') {
                    $bg             = $base;
                    $fg             = '#ffffff';
                    $event_title    = $room_name;
                    $platform_label = 'PriceLabs';
                } else if ($platform === 'airbnb') {
                    $bg             = $base;
                    $fg             = '#ffffff';
                    $event_title    = $room_name;
                    $platform_label = 'Airbnb';
                } else {
                    $bg             = cbc_tint_color($base);
                    $fg             = '#1a1a1a';
                    $event_title    = $room_name;
                    $platform_label = 'Booking.com';
                }

                $props = array(
                    'room'      => $room_name,
                    'platform'  => $platform_label,
                    'isBlocked' => $is_blocked,
                    'nights'    => isset($slot['nights']) ? $slot['nights'] : null,
                    'booked_on' => isset($slot['booked_on']) ? $slot['booked_on'] : '',
                    'formData'  => array(),
                );

                // ── 5. Match Fluent Forms entry by check-in date AND room.
                //      Submissions are sorted DESC, so the first match is the newest. ──
                if (!$is_blocked && !empty($form_data_entries)) {
                    foreach ($form_data_entries as $entry) {
                        $checkin_date    = '';
                        $submitted_room  = '';

                        foreach ($entry as $col_name => $col_val) {
                            $clean_col_name = strtolower(str_replace(array(' ', '-'), '', $col_name));

                            if (strpos($clean_col_name, 'checkin') !== false && empty($checkin_date)) {
                                $ts = strtotime($col_val);
                                if ($ts) $checkin_date = date('Y-m-d', $ts);
                            }
                            if ((strpos($clean_col_name, 'room') !== false || strpos($clean_col_name, 'apartment') !== false) && empty($submitted_room)) {
                                $submitted_room = trim(strtolower((string)$col_val));
                            }
                        }

                        if ($checkin_date !== $slot['start'])
                            continue;

                        $is_match = cbc_is_room_match($submitted_room, $room_name, $form_id, $rooms);

                        if ($is_match) {
                            $props['formData'] = $entry;
                            break; // newest match wins
                        }
                    }
                }

                $result[] = array(
                    'title'           => $event_title,
                    'start'           => $slot['start'],
                    'end'             => $slot['end'],
                    'backgroundColor' => $bg,
                    'borderColor'     => $is_blocked ? '#94a3b8' : $base,
                    'textColor'       => $fg,
                    'display'         => 'block',
                    'extendedProps'   => $props,
                );
            }
        }
    }

    // cbc_save_stored_ical($cal_id, $stored_all); // Replaced by database


    // ══════════════════════════════════════════════════════════════
    // SECTION 5b — HISTORICAL BACKFILL FROM FLUENT FORMS (DISABLED)
    //
    // Disabled as per user request: Fluent Form data should only be
    // shown when the corresponding slot is actively present in the 
    // PriceLabs API response. If PriceLabs doesn't return the slot,
    // the form entry will be ignored and no recovered booking will be created.
    // ══════════════════════════════════════════════════════════════

    // ── Global dedup safety net ──────────────────────────────────────
    // Remove any duplicate events for the same room + check-in date that
    // may have slipped through (e.g. iCal event AND a backfill for the
    // same slot). We dedup by room+start only (not end/checkout) because
    // the iCal checkout date and the form checkout date can differ slightly,
    // but two bookings for the same room on the same check-in are always
    // the same booking. The first occurrence wins (iCal events come first).
    $global_seen = array();
    $deduped     = array();
    foreach ($result as $ev) {
        $dedup_key = trim(strtolower($ev['extendedProps']['room'])) . '|' . $ev['start'];
        if (isset($global_seen[$dedup_key]))
            continue;
        $global_seen[$dedup_key] = 1;
        $deduped[] = $ev;
    }
    $result = $deduped;

    set_transient('cbc_events_' . $cal_id, $result, 3);
    return $result;
}

// ══════════════════════════════════════════════════════════════════
// SECTION 6 — LEGEND & SHORTCODE
// ══════════════════════════════════════════════════════════════════
add_shortcode('custom_booking_calendar', 'cbc_render_calendar');
function cbc_render_calendar($atts)
{
    $atts   = shortcode_atts(array('id' => ''), $atts);
    $cal_id = $atts['id'];
    if (empty($cal_id))
        return '<p><strong>Error:</strong> Please provide a Calendar ID in the shortcode.</p>';

    $calendars = get_option('cbc_calendars', array());
    if (!isset($calendars[$cal_id]))
        return '<p><strong>Error:</strong> Calendar ID not found.</p>';

    $calendar_data = $calendars[$cal_id];
    $rooms         = isset($calendar_data['rooms']) ? $calendar_data['rooms'] : array();

    $initial = cbc_get_merged_events($cal_id);
    $json    = wp_json_encode($initial);
    $ajax    = admin_url('admin-ajax.php');
    $nonce   = wp_create_nonce('cbc_nonce');
    $synced  = current_time('d M Y, H:i');

    ob_start();
?>
    <div class="cbc-wrapper" id="cbc-wrapper-<?php echo esc_attr($cal_id); ?>" data-cal-id="<?php echo esc_attr($cal_id); ?>">
        <div class="cbc-legend">
            <strong>Rooms:</strong>
            <?php foreach ($rooms as $room):
                $base = isset($room['color']) ? $room['color'] : '#333';
                $tint = cbc_tint_color($base);
                ?>
                <span class="cbc-legend-item">
                    <span class="cbc-swatch" style="background:<?php echo esc_attr($base); ?>;border-color:<?php echo esc_attr($base); ?>"></span>
                    <span class="cbc-swatch" style="background:<?php echo esc_attr($tint); ?>;border-color:<?php echo esc_attr($base); ?>"></span>
                    <?php echo esc_html($room['name']); ?>
                </span>
            <?php endforeach; ?>
            <span class="cbc-legend-divider">|</span>
            <span class="cbc-legend-key">Solid = PriceLabs &nbsp;|&nbsp; Airbnb &nbsp;|&nbsp; Light = Booking.com &nbsp;|&nbsp; ★ = Recovered &nbsp;|&nbsp; Grey = Blocked</span>
        </div>
        <div class="cbc-toolbar">
            <span class="cbc-sync-info"> Last synced: <strong class="cbc-last-synced"><?php echo esc_html($synced); ?></strong></span>
            <button class="cbc-refresh-btn">↺ Refresh Now</button>
        </div>
        <div class="booking-calendar"></div>
    </div>

<?php if (!defined('CBC_ASSETS_LOADED')):
        define('CBC_ASSETS_LOADED', true); ?>
    <div id="cbc-overlay" class="cbc-overlay" style="display:none;" onclick="cbcClosePopup()"></div>
    <div id="cbc-popup" class="cbc-popup" style="display:none;">
        <button class="cbc-popup-close" onclick="cbcClosePopup()">✕</button>
        <div id="cbc-popup-body"></div>
    </div>
    <style>
        .cbc-wrapper { max-width: 980px; margin: 0 auto 40px auto; font-family: inherit; position: relative; }
        .cbc-legend { display: flex; flex-wrap: wrap; align-items: center; gap: 10px; margin-bottom: 10px; padding: 9px 14px; background: #f8f9fa; border: 1px solid #dee2e6; border-radius: 6px; font-size: 13px; }
        .cbc-legend-item { display: flex; align-items: center; gap: 4px; white-space: nowrap; }
        .cbc-swatch { display: inline-block; width: 13px; height: 13px; border-radius: 3px; border: 2px solid #999; flex-shrink: 0; }
        .cbc-legend-divider { color: #ccc; }
        .cbc-legend-key { color: #666; font-size: 12px; }
        .cbc-toolbar { display: flex; align-items: center; justify-content: space-between; margin-bottom: 10px; font-size: 13px; color: #555; }
        .cbc-refresh-btn { background: #2c3e50; color: #fff; border: none; border-radius: 5px; padding: 6px 16px; font-size: 13px; cursor: pointer; transition: background .2s; }
        .cbc-refresh-btn:hover { background: #3d566e; }
        .cbc-refresh-btn.spinning { opacity: .65; pointer-events: none; }
        .booking-calendar { background: #fff; border: 1px solid #dee2e6; border-radius: 8px; padding: 12px; }

        .fc-daygrid-event { border-radius: 4px !important; font-size: 11.5px !important; cursor: pointer; border: none !important; margin-bottom: 2px !important; }

        .cbc-overlay { position: fixed; inset: 0; background: rgba(0,0,0,.5); z-index: 9998; backdrop-filter: blur(2px); }
        .cbc-popup { position: fixed; top: 50%; left: 50%; transform: translate(-50%,-50%); z-index: 9999; background: #fff; border-radius: 12px; box-shadow: 0 15px 40px rgba(0,0,0,.2); padding: 30px; width: 480px; max-width: 90vw; max-height: 85vh; overflow-y: auto; }
        .cbc-popup-close { position: absolute; top: 15px; right: 20px; background: none; border: none; font-size: 22px; cursor: pointer; color: #aaa; line-height: 1; }
        .cbc-popup-close:hover { color: #333; }

        .cbc-popup h3 { margin: 0 0 20px; font-size: 18px; border-bottom: 2px solid #f0f0f0; padding-bottom: 12px; display: flex; align-items: center; }
        .cbc-badge { padding: 3px 10px; border-radius: 20px; font-size: 11px; font-weight: 700; color: #fff; margin-left: 10px; text-transform: uppercase; letter-spacing: 0.5px; }
        .badge-pricelabs { background: #27ae60; }
        .badge-airbnb { background: #e74c3c; }
        .badge-booking { background: #2980b9; }
        .badge-blocked { background: #7f8c8d; }
        .badge-recovered { background: #8e44ad; }
        .cbc-field-container { display: flex; flex-direction: column; gap: 12px; }
        .cbc-field { background: #f8f9fa; border: 1px solid #e9ecef; padding: 12px 15px; border-radius: 8px; }
        .cbc-field-label { font-size: 12px; color: #6c757d; font-weight: 700; margin-bottom: 6px; line-height: 1.4; text-transform: uppercase; letter-spacing: 0.5px; }
        .cbc-field-val { font-size: 15px; color: #212529; font-weight: 500; word-break: break-word; line-height: 1.5; }

        .cbc-field-lock { background: #fff5f5; border-color: #ffc9c9; }
        .cbc-field-lock .cbc-field-label { color: #c0392b; }
        .cbc-field-lock .cbc-field-val { font-family: monospace; font-size: 18px; font-weight: 700; letter-spacing: 2px; color: #c0392b; }
    </style>
    <script>
        function cbcShowPopup(p, startStr, endStr) {
            var bc = 'badge-booking';
            if (p.isBlocked) bc = 'badge-blocked';
            else if (p.platform === 'PriceLabs') bc = 'badge-pricelabs';
            else if (p.platform === 'Airbnb') bc = 'badge-airbnb';
            else if (p.platform && p.platform.indexOf('Recovered') !== -1) bc = 'badge-recovered';

            var html = '<h3>' + cbcH(p.room) + '<span class="cbc-badge ' + bc + '">' + cbcH(p.platform) + '</span></h3>';
            html += '<div class="cbc-field-container">';
            html += '<div style="display:flex; gap:15px;">';
            html += cbcRow('Check-in Date', startStr, true);
            html += cbcRow('Check-out Date', endStr, true);
            if (p.nights !== null && p.nights !== undefined) {
                html += cbcRow('Nights', p.nights + ' night' + (p.nights !== 1 ? 's' : ''), true);
            }
            html += '</div>';
            if (p.booked_on) {
                html += '<div style="margin-top:6px; font-size:12px; color:#888;">📅 Booked on: ' + cbcH(p.booked_on) + '</div>';
            }

            if (p.isBlocked) {
                html += '<div style="margin-top:5px; font-size:14px; color:#555; font-weight:600;">This slot is manually blocked and not available for booking.</div>';
            } else {
                var formData = p.formData || {};
                var hasFormData = false;
                for (var columnName in formData) {
                    if (formData.hasOwnProperty(columnName)) {
                        var val = formData[columnName];
                        if (val === '' || val === null || val === undefined) continue;

                        hasFormData = true;
                        var lowerCol = columnName.toLowerCase();

                        if (lowerCol.indexOf('lock') !== -1 || lowerCol.indexOf('code') !== -1 || lowerCol.indexOf('pin') !== -1) {
                            html += cbcRowLock(' ' + columnName, val);
                        } else {
                            html += cbcRow(columnName, val);
                        }
                    }
                }
                if (!hasFormData) {
                    html += '<div style="margin-top:5px; font-size:13px; color:#888; font-style:italic;">No guest details found in Fluent Forms for this check-in date.</div>';
                }
            }

            html += '</div>';
            document.getElementById('cbc-popup-body').innerHTML = html;
            document.getElementById('cbc-popup').style.display = 'block';
            document.getElementById('cbc-overlay').style.display = 'block';
        }

        window.cbcClosePopup = function () {
            document.getElementById('cbc-popup').style.display = 'none';
            document.getElementById('cbc-overlay').style.display = 'none';
        };

        function cbcRow(label, val, flexChild = false) {
            var style = flexChild ? 'flex:1;' : '';
            return '<div class="cbc-field" style="' + style + '"><div class="cbc-field-label">' + cbcH(label) + '</div><div class="cbc-field-val">' + cbcH(val) + '</div></div>';
        }
        function cbcRowLock(label, val) {
            return '<div class="cbc-field cbc-field-lock"><div class="cbc-field-label">' + cbcH(label) + '</div><div class="cbc-field-val">' + cbcH(val) + '</div></div>';
        }
        function cbcH(s) {
            return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
        }
    </script>
<?php endif; ?>
    <script>
        window.cbcEvents = window.cbcEvents || {};
        window.cbcEvents["<?php echo esc_js($cal_id); ?>"] = <?php echo $json; ?>;

        document.addEventListener('DOMContentLoaded', function () {
            var wrapper = document.getElementById('cbc-wrapper-<?php echo esc_js($cal_id); ?>');
            var el  = wrapper.querySelector('.booking-calendar');
            var btn = wrapper.querySelector('.cbc-refresh-btn');
            var lbl = wrapper.querySelector('.cbc-last-synced');

            if (!el || typeof FullCalendar === 'undefined') return;

            var cal = new FullCalendar.Calendar(el, {
                initialView:      'dayGridMonth',
                height:           'auto',
                displayEventTime: false,
                dayMaxEvents:     false,
                headerToolbar: { left: 'prev,next today', center: 'title', right: 'dayGridMonth,listMonth' },
                events: window.cbcEvents["<?php echo esc_js($cal_id); ?>"],
                eventContent: function (arg) {
                    return {
                        html: '<div style="padding: 2px 6px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-weight: 600;">' + cbcH(arg.event.title) + '</div>'
                    };
                },
                eventClick: function (info) {
                    info.jsEvent.preventDefault();
                    cbcShowPopup(info.event.extendedProps, info.event.startStr, info.event.endStr);
                },
            });
            cal.render();

            var runSync = function (showSpinner) {
                if (showSpinner) {
                    btn.classList.add('spinning');
                    btn.textContent = '↺ Syncing…';
                }
                var fd = new FormData();
                fd.append('action', 'cbc_refresh');
                fd.append('nonce',  '<?php echo esc_js($nonce); ?>');
                fd.append('cal_id', '<?php echo esc_js($cal_id); ?>');
                fetch('<?php echo esc_js($ajax); ?>', { method: 'POST', body: fd })
                    .then(function (r) { return r.json(); })
                    .then(function (res) {
                        if (!res.success || !cal) return;
                        cal.removeAllEvents();
                        (res.data.events || []).forEach(function (ev) { cal.addEvent(ev); });
                        if (lbl) lbl.textContent = res.data.last_synced;
                    })
                    .catch(function (e) { console.warn('Refresh error:', e); })
                    .finally(function () {
                        if (showSpinner) {
                            btn.classList.remove('spinning');
                            btn.textContent = '↺ Refresh Now';
                        }
                    });
            };

            btn.addEventListener('click', function () { runSync(true); });
            setTimeout(function () { runSync(false); }, 200);
            setInterval(function () { runSync(false); }, 5000);
        });
    </script>
<?php
    return ob_get_clean();
}

// ══════════════════════════════════════════════════════════════════
// SECTION 7 — REST API FOR FLUTTER APP
// ══════════════════════════════════════════════════════════════════
add_action('rest_api_init', function () {
    register_rest_route('cbc/v1', '/calendars', array(
        'methods'             => 'GET',
        'callback'            => 'cbc_rest_get_all_calendars',
        'permission_callback' => function () { return current_user_can('manage_options'); },
    ));

    register_rest_route('cbc/v1', '/calendars/(?P<id>[a-zA-Z0-9_]+)/refresh', array(
        'methods'             => 'POST',
        'callback'            => 'cbc_rest_refresh_calendar',
        'permission_callback' => function () { return current_user_can('manage_options'); },
        'args'                => array(
            'id' => array('required' => true, 'sanitize_callback' => 'sanitize_text_field'),
        ),
    ));
});

function cbc_rest_get_all_calendars(WP_REST_Request $request)
{
    $calendars = get_option('cbc_calendars', array());
    if (!is_array($calendars) || empty($calendars))
        return new WP_REST_Response(array(), 200);

    $result = array();
    foreach ($calendars as $cal_id => $calendar) {
        $rooms_data = array();
        $rooms      = isset($calendar['rooms']) ? $calendar['rooms'] : array();
        foreach ($rooms as $room) {
            $rooms_data[] = array(
                'name'  => isset($room['name'])  ? $room['name']  : 'Unknown',
                'color' => isset($room['color']) ? $room['color'] : '#333333',
            );
        }
        $events = cbc_get_merged_events($cal_id);
        $result[] = array(
            'calendar_id'   => $cal_id,
            'calendar_name' => isset($calendar['name']) ? $calendar['name'] : 'Calendar',
            'rooms'         => $rooms_data,
            'events'        => $events,
            'last_synced'   => current_time('d M Y, H:i'),
        );
    }
    return new WP_REST_Response($result, 200);
}

function cbc_rest_refresh_calendar(WP_REST_Request $request)
{
    $cal_id    = $request->get_param('id');
    $calendars = get_option('cbc_calendars', array());
    if (!isset($calendars[$cal_id]))
        return new WP_REST_Response(array('message' => 'Calendar not found'), 404);

    delete_transient('cbc_events_' . $cal_id);

    $calendar   = $calendars[$cal_id];
    $rooms_data = array();
    $rooms      = isset($calendar['rooms']) ? $calendar['rooms'] : array();
    foreach ($rooms as $room) {
        $rooms_data[] = array(
            'name'  => isset($room['name'])  ? $room['name']  : 'Unknown',
            'color' => isset($room['color']) ? $room['color'] : '#333333',
        );
    }
    $events = cbc_get_merged_events($cal_id);

    $response = array(
        'calendar_id'   => $cal_id,
        'calendar_name' => isset($calendar['name']) ? $calendar['name'] : 'Calendar',
        'rooms'         => $rooms_data,
        'events'        => $events,
        'last_synced'   => current_time('d M Y, H:i'),
    );
    return new WP_REST_Response($response, 200);
}

// ══════════════════════════════════════════════════════════════════
// TEMPORARY FIX SCRIPT TO CLEAN DUPLICATES & ENFORCE UNIQUE KEY
// ══════════════════════════════════════════════════════════════════
add_action('admin_init', 'cbc_fix_duplicate_db_issue');
function cbc_fix_duplicate_db_issue() {
    if (isset($_GET['cbc_fix_db']) && current_user_can('manage_options')) {
        global $wpdb;
        $table_name = $wpdb->prefix . 'cbc_pricelabs_bookings_data';
        
        // 1. Delete all cancelled pricelabs bookings to clear out most duplicates
        $wpdb->query("DELETE FROM $table_name WHERE platform = 'pricelabs' AND status = 'cancelled'");
        
        // 2. Remove any remaining active duplicates (keep the one with max ID)
        $wpdb->query("
            DELETE t1 FROM $table_name t1
            INNER JOIN $table_name t2 
            WHERE t1.id < t2.id AND t1.uid = t2.uid
        ");
        
        // 3. Force add the UNIQUE KEY if it doesn't exist
        $indexes = $wpdb->get_results("SHOW INDEX FROM $table_name WHERE Key_name = 'booking_uid'");
        if (empty($indexes)) {
            $wpdb->query("ALTER TABLE $table_name ADD UNIQUE INDEX booking_uid (uid)");
            echo "<h2>✅ Database cleaned and Unique index added successfully.</h2>";
        } else {
            echo "<h2>✅ Database cleaned. Unique index already exists.</h2>";
        }
        
        echo "<p>All duplicates have been removed. You can now go back to your dashboard.</p>";
        exit;
    }
}
