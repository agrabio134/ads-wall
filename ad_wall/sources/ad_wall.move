#[allow(duplicate_alias, unused_variable)]
module sui_ad_wall::ad_wall {
    use sui::tx_context;
    use sui::object;
    use sui::coin;
    use sui::table;
    use 0x1::option;

    // Constants
    const GRID_WIDTH: u64 = 100;
    const GRID_HEIGHT: u64 = 100;
    const E_BLOCK_TAKEN: u64 = 1;
    const E_INVALID_SIZE: u64 = 2;
    const E_INSUFFICIENT_PAYMENT: u64 = 3;

    // Block metadata struct to store additional info
    public struct BlockInfo has copy, store {
        owner: address,
        image_cid: vector<u8>,
        width: u64,
        height: u64,
        is_top_left: bool,
    }

    // AdWall struct
    public struct AdWall has key, store {
        id: object::UID,
        owner: address,
        blocks: table::Table<u64, BlockInfo>, // block_id -> BlockInfo
        prices: table::Table<u64, u64>,       // block_id -> price in MIST
        base_price: u64,
        total_blocks_sold: u64,
    }

    // Event for block purchase
    public struct BlockPurchased has copy, drop {
        buyer: address,
        block_id: u64,
        width: u64,
        height: u64,
        image_cid: vector<u8>,
        price_paid: u64,
    }

    fun init(ctx: &mut tx_context::TxContext) {
        let wall = AdWall {
            id: object::new(ctx),
            owner: tx_context::sender(ctx),
            blocks: table::new(ctx),
            prices: table::new(ctx),
            base_price: 100_000_000, // 0.1 SUI
            total_blocks_sold: 0,
        };
        sui::transfer::transfer(wall, tx_context::sender(ctx));
    }

    fun to_block_id(x: u64, y: u64): u64 {
        assert!(x < GRID_WIDTH && y < GRID_HEIGHT, E_INVALID_SIZE);
        y * GRID_WIDTH + x
    }

    fun validate_purchase(wall: &AdWall, x: u64, y: u64, width: u64, height: u64) {
        assert!(x + width <= GRID_WIDTH && y + height <= GRID_HEIGHT, E_INVALID_SIZE);
        let mut i = 0;
        while (i < height) {
            let mut j = 0;
            while (j < width) {
                let block_id = to_block_id(x + j, y + i);
                assert!(!table::contains(&wall.blocks, block_id), E_BLOCK_TAKEN);
                j = j + 1;
            };
            i = i + 1;
        };
    }

    fun calculate_price(wall: &AdWall, num_blocks: u64): u64 {
        let base = wall.base_price;
        let dynamic_factor = (105 * wall.total_blocks_sold) / 100;
        let subtotal = base + (base * dynamic_factor / 100);
        let discount = if (num_blocks >= 21) {
            90
        } else if (num_blocks >= 6) {
            95
        } else {
            100
        };
        subtotal * num_blocks * discount / 100
    }

    public entry fun buy_blocks(
        wall: &mut AdWall,
        x: u64,
        y: u64,
        width: u64,
        height: u64,
        image_cid: vector<u8>,
        payment: &mut coin::Coin<0x2::sui::SUI>,
        ctx: &mut tx_context::TxContext
    ) {
        let sender = tx_context::sender(ctx);
        let num_blocks = width * height;

        validate_purchase(wall, x, y, width, height);

        let price = calculate_price(wall, num_blocks);

        // Check if the payment is sufficient
        assert!(coin::value(payment) >= price, E_INSUFFICIENT_PAYMENT);

        let paid = coin::split(payment, price, ctx);
        sui::transfer::public_transfer(paid, wall.owner);

        let mut i = 0;
        while (i < height) {
            let mut j = 0;
            while (j < width) {
                let block_id = to_block_id(x + j, y + i);
                let is_top_left = (i == 0 && j == 0);
                table::add(&mut wall.blocks, block_id, BlockInfo {
                    owner: sender,
                    image_cid,
                    width,
                    height,
                    is_top_left,
                });
                table::add(&mut wall.prices, block_id, price / num_blocks);
                j = j + 1;
            };
            i = i + 1;
        };

        wall.total_blocks_sold = wall.total_blocks_sold + num_blocks;

        sui::event::emit(BlockPurchased {
            buyer: sender,
            block_id: to_block_id(x, y),
            width,
            height,
            image_cid,
            price_paid: price,
        });
    }

    public fun get_block_owner(wall: &AdWall, block_id: u64): option::Option<address> {
        if (table::contains(&wall.blocks, block_id)) {
            option::some(table::borrow(&wall.blocks, block_id).owner)
        } else {
            option::none()
        }
    }

    public fun get_block_image(wall: &AdWall, block_id: u64): option::Option<vector<u8>> {
        if (table::contains(&wall.blocks, block_id)) {
            option::some(table::borrow(&wall.blocks, block_id).image_cid)
        } else {
            option::none()
        }
    }

    public fun get_block_info(wall: &AdWall, block_id: u64): option::Option<BlockInfo> {
        if (table::contains(&wall.blocks, block_id)) {
            option::some(*table::borrow(&wall.blocks, block_id))
        } else {
            option::none()
        }
    }

    public fun get_block_price(wall: &AdWall, block_id: u64): u64 {
        if (table::contains(&wall.prices, block_id)) {
            *table::borrow(&wall.prices, block_id)
        } else {
            wall.base_price
        }
    }
}