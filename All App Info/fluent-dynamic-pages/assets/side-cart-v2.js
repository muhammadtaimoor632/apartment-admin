jQuery(document).ready(function($) {
    const $cart = $('#fdp-side-cart');
    const $trigger = $('#fdp-cart-trigger');
    const $closeBtn = $('#fdp-cart-close');
    const $overlay = $('.fdp-cart-overlay');
    const $productList = $('#fdp-products-list');
    const $cartContents = $('#fdp-cart-contents');
    const $checkoutBtn = $('#fdp-checkout-btn');
    const $cartCount = $('.fdp-cart-count');
    
    let itemsInCart = 0;

    // Open/Close Cart
    $trigger.on('click', function() {
        $cart.addClass('fdp-open');
        fetchCartContents();
        if($productList.children('.fdp-product-item').length === 0) {
            fetchProducts();
        }
    });

    $closeBtn.add($overlay).on('click', function() {
        $cart.removeClass('fdp-open');
    });

    // Fetch Cart Contents via AJAX
    function fetchCartContents() {
        if ($cartContents.children().length === 0) {
            $cartContents.html('<div class="fdp-loading">Loading cart...</div>');
        } else {
            $cartContents.css('opacity', '0.5');
        }
        $.ajax({
            url: fdpCartObj.ajax_url,
            type: 'POST',
            data: {
                action: 'fdp_get_cart_contents'
            },
            success: function(response) {
                if(response.success) {
                    renderCartContents(response.data);
                } else {
                    $cartContents.empty();
                }
            },
            error: function() {
                $cartContents.html('<div style="color:red; text-align:center;">Failed to load cart.</div>');
            }
        });
    }

    function renderCartContents(data) {
        $cartContents.empty();
        $cartContents.css('opacity', '1');
        itemsInCart = data.count;
        updateCartUI();

        if (data.items && data.items.length > 0) {
            data.items.forEach(function(item) {
                const img = item.image ? `<img src="${item.image}" class="fdp-cart-item-image" alt="${item.product_name}">` : `<div class="fdp-cart-item-image"></div>`;
                
                const itemHtml = `
                    <div class="fdp-cart-item" data-key="${item.cart_item_key}">
                        ${img}
                        <div class="fdp-cart-item-details">
                            <h4 class="fdp-cart-item-title">${item.product_name}</h4>
                            <div class="fdp-cart-item-price">${item.price}</div>
                            <div class="fdp-cart-item-actions">
                                <button class="fdp-qty-btn fdp-qty-minus" data-key="${item.cart_item_key}" data-qty="${item.quantity - 1}">-</button>
                                <span class="fdp-qty-val">${item.quantity}</span>
                                <button class="fdp-qty-btn fdp-qty-plus" data-key="${item.cart_item_key}" data-qty="${item.quantity + 1}">+</button>
                            </div>
                        </div>
                        <button class="fdp-remove-btn" data-key="${item.cart_item_key}">&times;</button>
                    </div>
                `;
                $cartContents.append(itemHtml);
            });

            if (data.total) {
                $cartContents.append(`<div class="fdp-cart-total"><strong>Total:</strong> ${data.total}</div>`);
            }
        }
    }

    // Fetch Products via AJAX
    function fetchProducts() {
        $.ajax({
            url: fdpCartObj.ajax_url,
            type: 'POST',
            data: {
                action: 'fdp_get_products'
            },
            success: function(response) {
                if(response.success && response.data.length > 0) {
                    $productList.empty();
                    response.data.forEach(function(product) {
                        const img = product.image ? `<img src="${product.image}" class="fdp-product-image" alt="${product.name}">` : `<div class="fdp-product-image"></div>`;
                        
                        const itemHtml = `
                            <div class="fdp-product-item">
                                ${img}
                                <div class="fdp-product-details">
                                    <h4 class="fdp-product-title">${product.name}</h4>
                                    <div class="fdp-product-price">${product.price}</div>
                                </div>
                                <button class="fdp-add-btn" data-id="${product.id}">+</button>
                            </div>
                        `;
                        $productList.append(itemHtml);
                    });
                } else {
                    $productList.html('<div style="text-align:center; color:#64748b; padding: 20px;">No requests available at the moment.</div>');
                }
            },
            error: function() {
                $productList.html('<div style="color:red; text-align:center;">Failed to load items.</div>');
            }
        });
    }

    // Add to Cart
    $(document).on('click', '.fdp-add-btn', function() {
        const $btn = $(this);
        const productId = $btn.data('id');
        
        if($btn.hasClass('loading')) return;
        
        $btn.addClass('loading').html('...');
        
        $.ajax({
            url: fdpCartObj.ajax_url,
            type: 'POST',
            data: {
                action: 'fdp_add_to_cart',
                product_id: productId,
                bedroom_number: fdpCartObj.bedroom_number
            },
            success: function(response) {
                if(response.success) {
                    $btn.removeClass('loading').html('✓').css('background', '#10b981');
                    fetchCartContents(); // Refresh cart
                    
                    setTimeout(() => {
                        $btn.html('+').css('background', '');
                    }, 2000);
                } else {
                    $btn.removeClass('loading').html('+');
                    alert('Error adding item.');
                }
            },
            error: function() {
                $btn.removeClass('loading').html('+');
            }
        });
    });

    // Update Quantity
    $(document).on('click', '.fdp-qty-btn', function() {
        const $btn = $(this);
        const cartItemKey = $btn.data('key');
        const qty = $btn.data('qty');
        
        $cartContents.css('opacity', '0.5');
        
        $.ajax({
            url: fdpCartObj.ajax_url,
            type: 'POST',
            data: {
                action: 'fdp_update_cart_quantity',
                cart_item_key: cartItemKey,
                quantity: qty
            },
            success: function(response) {
                if(response.success) {
                    fetchCartContents();
                } else {
                    $cartContents.css('opacity', '1');
                    alert('Error updating quantity.');
                }
            },
            error: function() {
                $cartContents.css('opacity', '1');
            }
        });
    });

    // Remove from Cart
    $(document).on('click', '.fdp-remove-btn', function() {
        const $btn = $(this);
        const cartItemKey = $btn.data('key');
        
        $cartContents.css('opacity', '0.5');
        
        $.ajax({
            url: fdpCartObj.ajax_url,
            type: 'POST',
            data: {
                action: 'fdp_remove_from_cart',
                cart_item_key: cartItemKey
            },
            success: function(response) {
                if(response.success) {
                    fetchCartContents();
                } else {
                    $cartContents.css('opacity', '1');
                    alert('Error removing item.');
                }
            },
            error: function() {
                $cartContents.css('opacity', '1');
            }
        });
    });

    function updateCartUI() {
        if(itemsInCart > 0) {
            $cartCount.text(itemsInCart).show();
            $checkoutBtn.prop('disabled', false).text(`Proceed to Checkout (${itemsInCart} items)`);
            $('#fdp-cart-toggle-btn').show();
        } else {
            $cartCount.hide();
            $checkoutBtn.prop('disabled', true).text('Proceed to Checkout');
            $('#fdp-cart-section').slideUp(200);
            $('#fdp-cart-toggle-btn').hide();
            $('#fdp-cart-toggle-btn span').text('Show Cart');
        }
    }

    $(document).on('click', '#fdp-cart-toggle-btn', function() {
        $('#fdp-cart-section').slideToggle(200, function() {
            if ($('#fdp-cart-section').is(':visible')) {
                $('#fdp-cart-toggle-btn span').text('Hide Cart');
            } else {
                $('#fdp-cart-toggle-btn span').text('Show Cart');
            }
        });
    });

    // Proceed to Checkout
    $checkoutBtn.on('click', function() {
        if(itemsInCart > 0 && fdpCartObj.checkout_url) {
            // Save bedroom number to cookie so PHP can read it during WC checkout
            if(fdpCartObj.bedroom_number) {
                document.cookie = "fdp_bedroom_number=" + encodeURIComponent(fdpCartObj.bedroom_number) + "; path=/; max-age=86400"; // 1 day
            }
            $checkoutBtn.text('Redirecting...');
            window.location.href = fdpCartObj.checkout_url;
        }
    });
});
