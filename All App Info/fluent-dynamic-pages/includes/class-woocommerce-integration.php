<?php
if (!defined('ABSPATH')) {
    exit;
}

class FDP_WooCommerce_Integration {

    public function __construct() {
        // Enqueue assets for the side cart
        add_action('wp_enqueue_scripts', array($this, 'enqueue_assets'));
        
        // Output side cart HTML in footer
        add_action('wp_footer', array($this, 'render_side_cart'));

        // Handle WooCommerce Checkout to capture Bedroom Number
        add_action('woocommerce_checkout_update_order_meta', array($this, 'save_bedroom_number_to_order'));
        add_action('woocommerce_store_api_checkout_update_order_from_request', array($this, 'save_bedroom_number_to_order_blocks'), 10, 2);

        // Register custom REST API endpoint for the app
        add_action('rest_api_init', array($this, 'register_guest_requests_endpoint'));
        
        // Custom AJAX endpoints for the cart
        add_action('wp_ajax_fdp_get_products', array($this, 'get_products'));
        add_action('wp_ajax_nopriv_fdp_get_products', array($this, 'get_products'));
        
        add_action('wp_ajax_fdp_add_to_cart', array($this, 'add_to_cart'));
        add_action('wp_ajax_nopriv_fdp_add_to_cart', array($this, 'add_to_cart'));
        
        // New endpoints for cart management
        add_action('wp_ajax_fdp_get_cart_contents', array($this, 'get_cart_contents'));
        add_action('wp_ajax_nopriv_fdp_get_cart_contents', array($this, 'get_cart_contents'));

        add_action('wp_ajax_fdp_remove_from_cart', array($this, 'remove_from_cart'));
        add_action('wp_ajax_nopriv_fdp_remove_from_cart', array($this, 'remove_from_cart'));
        
        add_action('wp_ajax_fdp_update_cart_quantity', array($this, 'update_cart_quantity'));
        add_action('wp_ajax_nopriv_fdp_update_cart_quantity', array($this, 'update_cart_quantity'));
    }

    public function enqueue_assets() {
        // Only load on our dynamic pages
        if (!is_singular('fluent_dynamic_page')) {
            return;
        }

        wp_enqueue_style('fdp-side-cart-css', FF_DYNAMIC_PAGES_URL . 'assets/side-cart.css', array(), FF_DYNAMIC_PAGES_VERSION);
        wp_enqueue_script('fdp-side-cart-js', FF_DYNAMIC_PAGES_URL . 'assets/side-cart.js', array('jquery'), FF_DYNAMIC_PAGES_VERSION, true);

        // Extract Bedroom Number from Fluent Forms submission if available
        global $post;
        $bedroom_number = get_the_title($post->ID); 
        $identifier_field = get_post_meta($post->ID, '_fdp_order_identifier_field', true);
        
        if(isset($_GET['fdp_hash'])) {
            global $wpdb;
            $hash = sanitize_text_field($_GET['fdp_hash']);
            $table_name = $wpdb->prefix . 'fdp_generated_links';
            $link_record = $wpdb->get_row($wpdb->prepare("SELECT submission_id FROM {$table_name} WHERE hash = %s", $hash));
            if($link_record) {
                $submission = $wpdb->get_row($wpdb->prepare("SELECT response FROM {$wpdb->prefix}fluentform_submissions WHERE id = %d", $link_record->submission_id));
                if($submission) {
                    $data = json_decode($submission->response, true);
                    
                    $field_value = '';
                    if (!empty($identifier_field)) {
                        // Extract field name if user accidentally pasted the shortcode
                        if (preg_match('/field="([^"]+)"/', $identifier_field, $matches)) {
                            $identifier_field = $matches[1];
                        }
                        
                        // Support dot notation for nested fields (e.g. names.first_name)
                        $keys = explode('.', $identifier_field);
                        $current_data = $data;
                        $found = true;
                        foreach ($keys as $key) {
                            if (is_array($current_data) && isset($current_data[$key])) {
                                $current_data = $current_data[$key];
                            } else {
                                $found = false;
                                break;
                            }
                        }
                        if ($found && !is_array($current_data) && !empty($current_data)) {
                            $field_value = $current_data;
                        }
                    }

                    if (!empty($field_value)) {
                        $bedroom_number .= ' - ' . $field_value;
                    } elseif(isset($data['apartment_number']) && !empty($data['apartment_number'])) {
                        $bedroom_number .= ' - ' . $data['apartment_number'];
                    } elseif (isset($data['bedroom_number']) && !empty($data['bedroom_number'])) {
                        $bedroom_number .= ' - ' . $data['bedroom_number'];
                    }
                }
            }
        }

        wp_localize_script('fdp-side-cart-js', 'fdpCartObj', array(
            'ajax_url' => admin_url('admin-ajax.php'),
            'checkout_url' => function_exists('wc_get_checkout_url') ? wc_get_checkout_url() : '',
            'bedroom_number' => $bedroom_number
        ));
    }

    public function render_side_cart() {
        if (!is_singular('fluent_dynamic_page')) {
            return;
        }
        ?>
        <!-- Side Cart Trigger Button -->
        <button id="fdp-cart-trigger" class="fdp-cart-trigger">
            <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M6 2L3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4z"></path><line x1="3" y1="6" x2="21" y2="6"></line><path d="M16 10a4 4 0 0 1-8 0"></path></svg>
            <span class="fdp-cart-count" style="display:none;">0</span>
        </button>

        <!-- Side Cart Drawer -->
        <div id="fdp-side-cart" class="fdp-side-cart">
            <div class="fdp-cart-overlay"></div>
            <div class="fdp-cart-panel">
                <div class="fdp-cart-header">
                    <h2>Request Extras</h2>
                    <button id="fdp-cart-close" class="fdp-cart-close">&times;</button>
                </div>
                <div class="fdp-cart-body">
                    <h3 class="fdp-available-title">Available Extras</h3>
                    <div id="fdp-products-list" class="fdp-products-list">
                        <div class="fdp-loading">Loading available requests...</div>
                    </div>
                </div>
                <div class="fdp-cart-footer">
                    <button id="fdp-cart-toggle-btn" class="fdp-cart-toggle-btn" style="display:none; width: 100%; margin-bottom: 12px; background: transparent; border: 2px solid var(--fdp-primary); color: var(--fdp-primary); padding: 10px; border-radius: 8px; font-weight: 600; cursor: pointer;">
                        <span>Show Cart</span>
                    </button>
                    <div id="fdp-cart-section" style="display: none; margin-bottom: 16px; max-height: 40vh; overflow-y: auto; padding-right: 8px;">
                        <!-- Current Cart Items section -->
                        <div id="fdp-cart-contents" class="fdp-cart-contents">
                            <!-- Loaded dynamically -->
                        </div>
                    </div>
                    <button id="fdp-checkout-btn" class="fdp-checkout-btn" disabled>Proceed to Checkout</button>
                </div>
            </div>
        </div>
        <?php
    }

    public function get_products() {
        if (!class_exists('WooCommerce')) {
            wp_send_json_error('WooCommerce not installed');
        }

        $args = array(
            'status' => 'publish',
            'limit' => 20,
        );
        $products = wc_get_products($args);
        
        $data = array();
        foreach ($products as $product) {
            $image_id  = $product->get_image_id();
            $image_url = $image_id ? wp_get_attachment_image_url($image_id, 'thumbnail') : '';
            
            $data[] = array(
                'id' => $product->get_id(),
                'name' => $product->get_name(),
                'price' => $product->get_price_html(),
                'image' => $image_url,
                'raw_price' => $product->get_price()
            );
        }

        wp_send_json_success($data);
    }

    public function add_to_cart() {
        if (!class_exists('WooCommerce')) {
            wp_send_json_error('WooCommerce not installed');
        }

        $product_id = isset($_POST['product_id']) ? intval($_POST['product_id']) : 0;
        $quantity = isset($_POST['quantity']) ? intval($_POST['quantity']) : 1;
        $bedroom_number = isset($_POST['bedroom_number']) ? sanitize_text_field($_POST['bedroom_number']) : '';
        
        if ($product_id > 0) {
            WC()->cart->add_to_cart($product_id, $quantity);
            if (!empty($bedroom_number) && isset(WC()->session)) {
                WC()->session->set('fdp_bedroom_number', $bedroom_number);
            }
            wp_send_json_success('Added to cart');
        } else {
            wp_send_json_error('Invalid product');
        }
    }

    public function get_cart_contents() {
        if (!class_exists('WooCommerce') || is_null(WC()->cart)) {
            wp_send_json_error('WooCommerce or Cart not initialized');
        }

        $cart_items = array();
        $total = WC()->cart->get_cart_total();
        $count = WC()->cart->get_cart_contents_count();

        foreach (WC()->cart->get_cart() as $cart_item_key => $cart_item) {
            $_product = apply_filters('woocommerce_cart_item_product', $cart_item['data'], $cart_item, $cart_item_key);
            $product_id = apply_filters('woocommerce_cart_item_product_id', $cart_item['product_id'], $cart_item, $cart_item_key);
            
            if ($_product && $_product->exists() && $cart_item['quantity'] > 0 && apply_filters('woocommerce_widget_cart_item_visible', true, $cart_item, $cart_item_key)) {
                $image_id  = $_product->get_image_id();
                $image_url = $image_id ? wp_get_attachment_image_url($image_id, 'thumbnail') : '';
                
                $cart_items[] = array(
                    'cart_item_key' => $cart_item_key,
                    'product_id' => $product_id,
                    'product_name' => $_product->get_name(),
                    'quantity' => $cart_item['quantity'],
                    'price' => WC()->cart->get_product_price($_product),
                    'image' => $image_url
                );
            }
        }

        wp_send_json_success(array(
            'items' => $cart_items,
            'total' => $total,
            'count' => $count
        ));
    }

    public function remove_from_cart() {
        if (!class_exists('WooCommerce') || is_null(WC()->cart)) {
            wp_send_json_error('WooCommerce or Cart not initialized');
        }
        $cart_item_key = isset($_POST['cart_item_key']) ? sanitize_text_field($_POST['cart_item_key']) : '';
        if ($cart_item_key && WC()->cart->remove_cart_item($cart_item_key)) {
            wp_send_json_success();
        }
        wp_send_json_error();
    }

    public function update_cart_quantity() {
        if (!class_exists('WooCommerce') || is_null(WC()->cart)) {
            wp_send_json_error('WooCommerce or Cart not initialized');
        }
        $cart_item_key = isset($_POST['cart_item_key']) ? sanitize_text_field($_POST['cart_item_key']) : '';
        $quantity = isset($_POST['quantity']) ? intval($_POST['quantity']) : 0;
        
        if ($cart_item_key && $quantity > 0) {
            WC()->cart->set_quantity($cart_item_key, $quantity);
            wp_send_json_success();
        } elseif ($cart_item_key && $quantity === 0) {
            WC()->cart->remove_cart_item($cart_item_key);
            wp_send_json_success();
        }
        wp_send_json_error();
    }


    public function save_bedroom_number_to_order($order_id) {
        $bedroom_number = '';
        if (isset($_COOKIE['fdp_bedroom_number'])) {
            $bedroom_number = sanitize_text_field(stripslashes($_COOKIE['fdp_bedroom_number']));
        } elseif (isset(WC()->session) && WC()->session->get('fdp_bedroom_number')) {
            $bedroom_number = WC()->session->get('fdp_bedroom_number');
        }

        if (!empty($bedroom_number)) {
            update_post_meta($order_id, '_fdp_bedroom_number', $bedroom_number);
            
            $order = wc_get_order($order_id);
            if ($order) {
                $order->add_order_note("Guest Request for Bedroom/Apartment: " . $bedroom_number);
            }
        }
    }

    public function save_bedroom_number_to_order_blocks($order, $request) {
        $bedroom_number = '';
        if (isset($_COOKIE['fdp_bedroom_number'])) {
            $bedroom_number = sanitize_text_field(stripslashes($_COOKIE['fdp_bedroom_number']));
        } elseif (isset(WC()->session) && WC()->session->get('fdp_bedroom_number')) {
            $bedroom_number = WC()->session->get('fdp_bedroom_number');
        }
        
        if (!empty($bedroom_number)) {
            $order->update_meta_data('_fdp_bedroom_number', $bedroom_number);
            $order->add_order_note("Guest Request for Bedroom/Apartment: " . $bedroom_number);
        }
    }

    public function register_guest_requests_endpoint() {
        register_rest_route('fluent_dynamic/v1', '/guest-requests', array(
            'methods' => 'GET',
            'callback' => array($this, 'get_guest_requests_api'),
            'permission_callback' => '__return_true'
        ));
    }

    public function get_guest_requests_api($request) {
        if (!class_exists('WooCommerce')) {
            return new WP_Error('wc_missing', 'WooCommerce is not active', array('status' => 500));
        }

        $args = array(
            'limit' => 20,
            'orderby' => 'date',
            'order' => 'DESC',
            'return' => 'objects',
        );

        $orders = wc_get_orders($args);
        $results = array();

        foreach ($orders as $order) {
            $bedroom_number = $order->get_meta('_fdp_bedroom_number');
            if (empty($bedroom_number)) {
                $bedroom_number = 'Direct Order';
            }
            
            $items = array();
            foreach ($order->get_items() as $item_id => $item) {
                $items[] = array(
                    'product_name' => $item->get_name(),
                    'quantity' => $item->get_quantity(),
                    'total' => $item->get_total()
                );
            }

            $results[] = array(
                'order_id'       => $order->get_id(),
                'guest_name'     => trim($order->get_billing_first_name() . ' ' . $order->get_billing_last_name()),
                'status'         => $order->get_status(),
                'date'           => $order->get_date_created()->date('Y-m-d H:i:s'),
                'bedroom_number' => $bedroom_number,
                'total'          => $order->get_total(),
                'items'          => $items
            );
        }

        return rest_ensure_response($results);
    }
}
