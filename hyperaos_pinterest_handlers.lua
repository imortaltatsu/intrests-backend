-- Pinterest-like App with HyperAOS 2.0.7
-- Doom scrolling social media app with wallet integration and external API

-- Initialize HyperAOS process
if not id then
    id = "hyperaos_process_" .. os.time()
end

-- Global variables (HyperAOS style)
Name = "PinterestLikeApp"
owner = id
Version = "1.0.0"
Created = os.time()

-- App configuration
local APP_CONFIG = {
    relay_device = "~relay@1.0",
    patch_device = "~patch@1.0",
    api_gateway = "https://vector.adityaberry.me/docs#/",
    max_posts_per_page = 20
}

-- Storage for app data (HyperAOS synchronized state)
Users = {}
Posts = {}
Likes = {}
Follows = {}
Wallets = {}
FeedCache = {}
Analytics = {
    total_users = 0,
    total_posts = 0,
    total_likes = 0,
    total_follows = 0
}

-- Utility functions
local function log_app_event(event, data)
    print("[" .. os.date("%Y-%m-%d %H:%M:%S") .. "] PinterestApp: " .. event .. " - " .. (data or ""))
end

local function send_app_response(target, data, tags)
    send({
        target = target,
        data = data,
        tags = tags or {}
    })
end

local function update_analytics(event_type)
    if event_type == "user_created" then
        Analytics.total_users = Analytics.total_users + 1
    elseif event_type == "post_created" then
        Analytics.total_posts = Analytics.total_posts + 1
    elseif event_type == "like_created" then
        Analytics.total_likes = Analytics.total_likes + 1
    elseif event_type == "follow_created" then
        Analytics.total_follows = Analytics.total_follows + 1
    end
end

-- Handler 1: User Registration with Wallet
Handlers.add("user_registration",
    function(msg)
        return msg.tags and msg.tags.Type == "UserRegistration"
    end,
    function(msg)
        local username = msg.tags.Username
        local wallet_address = msg.tags.WalletAddress
        local user_id = msg.from
        
        if username and wallet_address then
            Users[user_id] = {
                id = user_id,
                username = username,
                wallet_address = wallet_address,
                created_at = os.time(),
                status = "active",
                profile = {
                    bio = msg.tags.Bio or "",
                    avatar = msg.tags.Avatar or "",
                    followers_count = 0,
                    following_count = 0,
                    posts_count = 0
                }
            }
            
            -- Store wallet info
            Wallets[wallet_address] = {
                address = wallet_address,
                owner = user_id,
                balance = 0,
                created_at = os.time()
            }
            
            update_analytics("user_created")
            
            send_app_response(msg.from, "User registered: " .. username, {
                { name = "Type", value = "UserRegistered" },
                { name = "Success", value = "true" },
                { name = "UserId", value = user_id },
                { name = "Username", value = username },
                { name = "WalletAddress", value = wallet_address }
            })
            
            log_app_event("USER_REGISTERED", "User: " .. username .. " Wallet: " .. wallet_address)
        else
            send_app_response(msg.from, "Error: Missing username or wallet address", {
                { name = "Type", value = "UserRegistrationError" },
                { name = "Success", value = "false" }
            })
        end
    end
)

-- Handler 2: Create Post with External API
Handlers.add("create_post",
    function(msg)
        return msg.tags and msg.tags.Type == "CreatePost"
    end,
    function(msg)
        local user_id = msg.from
        local post_title = msg.tags.PostTitle
        local post_description = msg.data
        local image_url = msg.tags.ImageUrl
        local post_id = "post_" .. os.time() .. "_" .. string.sub(user_id, 1, 8)
        
        if post_title and Users[user_id] then
            -- Create post locally
            Posts[post_id] = {
                id = post_id,
                title = post_title,
                description = post_description or "",
                image_url = image_url or "",
                author = user_id,
                created_at = os.time(),
                likes_count = 0,
                comments_count = 0,
                shares_count = 0
            }
            
            -- Update user post count
            Users[user_id].profile.posts_count = Users[user_id].profile.posts_count + 1
            
            update_analytics("post_created")
            
            -- Send to external API via relay
            send({
                target = APP_CONFIG.relay_device,
                data = json.encode({
                    title = post_title,
                    description = post_description,
                    image_url = image_url,
                    author = user_id,
                    wallet_address = Users[user_id].wallet_address
                }),
                tags = {
                    { name = "Type", value = "RelayPost" },
                    { name = "resolve", value = APP_CONFIG.relay_device .. "/call/" .. APP_CONFIG.patch_device },
                    { name = "relay-path", value = APP_CONFIG.api_gateway .. "posts" },
                    { name = "relay-method", value = "POST" },
                    { name = "relay-body", value = json.encode({
                        title = post_title,
                        description = post_description,
                        image_url = image_url,
                        author = user_id,
                        wallet_address = Users[user_id].wallet_address
                    }) },
                    { name = "Content-Type", value = "application/json" },
                    { name = "action", value = "PostCreated" },
                    { name = "PostId", value = post_id }
                }
            })
            
            send_app_response(msg.from, "Post created: " .. post_title, {
                { name = "Type", value = "PostCreated" },
                { name = "Success", value = "true" },
                { name = "PostId", value = post_id },
                { name = "PostTitle", value = post_title }
            })
            
            log_app_event("POST_CREATED", "Post: " .. post_title)
        else
            send_app_response(msg.from, "Error: Missing post title or user not found", {
                { name = "Type", value = "PostCreationError" },
                { name = "Success", value = "false" }
            })
        end
    end
)

-- Handler 3: Like/Unlike Post
Handlers.add("like_post",
    function(msg)
        return msg.tags and msg.tags.Type == "LikePost"
    end,
    function(msg)
        local user_id = msg.from
        local post_id = msg.tags.PostId
        local action = msg.tags.Action or "like" -- "like" or "unlike"
        
        if post_id and Posts[post_id] and Users[user_id] then
            local like_key = user_id .. "_" .. post_id
            
            if action == "like" then
                if not Likes[like_key] then
                    Likes[like_key] = {
                        user_id = user_id,
                        post_id = post_id,
                        liked_at = os.time()
                    }
                    
                    Posts[post_id].likes_count = Posts[post_id].likes_count + 1
                    update_analytics("like_created")
                    
                    send_app_response(msg.from, "Post liked: " .. post_id, {
                        { name = "Type", value = "PostLiked" },
                        { name = "Success", value = "true" },
                        { name = "PostId", value = post_id },
                        { name = "LikesCount", value = tostring(Posts[post_id].likes_count) }
                    })
                    
                    log_app_event("POST_LIKED", "Post: " .. post_id .. " by: " .. user_id)
                else
                    send_app_response(msg.from, "Post already liked", {
                        { name = "Type", value = "PostAlreadyLiked" },
                        { name = "Success", value = "false" }
                    })
                end
                
            elseif action == "unlike" then
                if Likes[like_key] then
                    Likes[like_key] = nil
                    Posts[post_id].likes_count = Posts[post_id].likes_count - 1
                    
                    send_app_response(msg.from, "Post unliked: " .. post_id, {
                        { name = "Type", value = "PostUnliked" },
                        { name = "Success", value = "true" },
                        { name = "PostId", value = post_id },
                        { name = "LikesCount", value = tostring(Posts[post_id].likes_count) }
                    })
                    
                    log_app_event("POST_UNLIKED", "Post: " .. post_id .. " by: " .. user_id)
                else
                    send_app_response(msg.from, "Post not liked", {
                        { name = "Type", value = "PostNotLiked" },
                        { name = "Success", value = "false" }
                    })
                end
            end
        else
            send_app_response(msg.from, "Error: Missing post ID, post not found, or user not found", {
                { name = "Type", value = "LikeError" },
                { name = "Success", value = "false" }
            })
        end
    end
)

-- Handler 4: Process API Response (Video Content)
Handlers.add("process_api_response",
    function(msg)
        return msg.tags and msg.tags.Type == "API-Response"
    end,
    function(msg)
        local user_id = msg.tags.UserId or msg.from
        local api_endpoint = msg.tags.ApiEndpoint
        local response_data = msg.data
        
        if response_data and Users[user_id] then
            local success, api_result = pcall(json.decode, response_data)
            
            if success and api_result.index_version and api_result.results then
                local processed_posts = {}
                
                -- Process each result from the API
                for i, result in ipairs(api_result.results) do
                    if result.metadata then
                        local metadata = result.metadata
                        local post_id = "api_post_" .. os.time() .. "_" .. i
                        
                        -- Create post from API data
                        local post_data = {
                            id = post_id,
                            title = metadata.description or "Untitled Content",
                            description = metadata.description or "",
                            image_url = result.id or "",
                            video_url = result.id or "",
                            author = metadata.author or "Unknown",
                            created_at = os.time(),
                            likes_count = 0,
                            comments_count = 0,
                            shares_count = 0,
                            source = "api",
                            api_data = {
                                original_id = result.id,
                                score = result.score,
                                modality = metadata.modality,
                                content_type = metadata.content_type,
                                language = metadata.language,
                                keywords = metadata.keywords,
                                arns_status = metadata.arns_status
                            }
                        }
                        
                        -- Store the post
                        Posts[post_id] = post_data
                        
                        -- Add to processed posts
                        table.insert(processed_posts, {
                            id = post_data.id,
                            title = post_data.title,
                            description = post_data.description,
                            image_url = post_data.image_url,
                            video_url = post_data.video_url,
                            author = post_data.author,
                            modality = metadata.modality,
                            content_type = metadata.content_type,
                            score = result.score,
                            created_at = post_data.created_at
                        })
                        
                        update_analytics("post_created")
                    end
                end
                
                send_app_response(msg.from, "API Response Processed: " .. json.encode({
                    index_version = api_result.index_version,
                    processed_count = #processed_posts,
                    posts = processed_posts
                }), {
                    { name = "Type", value = "APIResponseProcessed" },
                    { name = "Success", value = "true" },
                    { name = "IndexVersion", value = tostring(api_result.index_version) },
                    { name = "ProcessedCount", value = tostring(#processed_posts) },
                    { name = "ApiEndpoint", value = api_endpoint or "unknown" }
                })
                
                log_app_event("API_RESPONSE_PROCESSED", "User: " .. user_id .. " Processed: " .. #processed_posts .. " posts")
            else
                send_app_response(msg.from, "Error: Invalid API response format", {
                    { name = "Type", value = "APIResponseError" },
                    { name = "Success", value = "false" },
                    { name = "Error", value = "Invalid JSON or missing required fields" }
                })
            end
        else
            send_app_response(msg.from, "Error: Missing response data or user not found", {
                { name = "Type", value = "APIResponseError" },
                { name = "Success", value = "false" }
            })
        end
    end
)

-- Handler 5: Search External Content
Handlers.add("search_external_content",
    function(msg)
        return msg.tags and msg.tags.Type == "SearchExternalContent"
    end,
    function(msg)
        local user_id = msg.from
        local search_query = msg.tags.SearchQuery
        local modality = msg.tags.Modality or "all" -- "video", "image", "text", "all"
        local limit = msg.tags.Limit or "10"
        
        if search_query and Users[user_id] then
            -- Make search request via HyperBEAM relay
            local search_body = json.encode({
                query = search_query,
                modality = modality,
                limit = tonumber(limit)
            })
            
            send({
                target = APP_CONFIG.relay_device,
                data = search_body,
                tags = {
                    { name = "Type", value = "RelaySearchCall" },
                    { name = "resolve", value = APP_CONFIG.relay_device .. "/call/" .. APP_CONFIG.patch_device },
                    { name = "relay-path", value = APP_CONFIG.api_gateway .. "search" },
                    { name = "relay-method", value = "POST" },
                    { name = "relay-body", value = search_body },
                    { name = "Content-Type", value = "application/json" },
                    { name = "action", value = "API-Response" },
                    { name = "UserId", value = user_id },
                    { name = "SearchQuery", value = search_query },
                    { name = "Modality", value = modality }
                }
            })
            
            send_app_response(msg.from, "External search initiated for: " .. search_query, {
                { name = "Type", value = "ExternalSearchInitiated" },
                { name = "Success", value = "true" },
                { name = "SearchQuery", value = search_query },
                { name = "Modality", value = modality },
                { name = "Limit", value = limit }
            })
            
            log_app_event("EXTERNAL_SEARCH", "User: " .. user_id .. " Query: " .. search_query)
        else
            send_app_response(msg.from, "Error: Missing search query or user not found", {
                { name = "Type", value = "ExternalSearchError" },
                { name = "Success", value = "false" }
            })
        end
    end
)

-- Handler 6: Get Feed (Doom Scrolling)
Handlers.add("get_feed",
    function(msg)
        return msg.tags and msg.tags.Type == "GetFeed"
    end,
    function(msg)
        local user_id = msg.from
        local page = tonumber(msg.tags.Page) or 1
        local limit = tonumber(msg.tags.Limit) or APP_CONFIG.max_posts_per_page
        local feed_type = msg.tags.FeedType or "all" -- "all", "following", "trending"
        
        if Users[user_id] then
            local feed_posts = {}
            local start_index = (page - 1) * limit + 1
            local end_index = start_index + limit - 1
            local current_index = 1
            
            -- Collect posts based on feed type
            for post_id, post in pairs(Posts) do
                local include_post = false
                
                if feed_type == "all" then
                    include_post = true
                elseif feed_type == "following" then
                    -- Check if user follows the post author
                    local follow_key = user_id .. "_" .. post.author
                    include_post = Follows[follow_key] ~= nil
                elseif feed_type == "trending" then
                    -- Include posts with high engagement
                    include_post = post.likes_count > 5 or post.comments_count > 2
                end
                
                if include_post and current_index >= start_index and current_index <= end_index then
                    local author = Users[post.author]
                    local is_liked = Likes[user_id .. "_" .. post_id] ~= nil
                    
                    table.insert(feed_posts, {
                        id = post.id,
                        title = post.title,
                        description = post.description,
                        image_url = post.image_url,
                        video_url = post.video_url,
                        author = {
                            id = post.author,
                            username = author and author.username or "Unknown",
                            avatar = author and author.profile.avatar or ""
                        },
                        created_at = post.created_at,
                        likes_count = post.likes_count,
                        comments_count = post.comments_count,
                        shares_count = post.shares_count,
                        is_liked = is_liked,
                        modality = post.api_data and post.api_data.modality or "unknown",
                        source = post.source or "local"
                    })
                end
                
                if include_post then
                    current_index = current_index + 1
                end
            end
            
            -- Sort by creation time (newest first)
            table.sort(feed_posts, function(a, b) return a.created_at > b.created_at end)
            
            send_app_response(msg.from, "Feed: " .. json.encode(feed_posts), {
                { name = "Type", value = "FeedData" },
                { name = "Success", value = "true" },
                { name = "FeedType", value = feed_type },
                { name = "Page", value = tostring(page) },
                { name = "PostCount", value = tostring(#feed_posts) }
            })
            
            log_app_event("FEED_REQUESTED", "User: " .. user_id .. " Type: " .. feed_type)
        else
            send_app_response(msg.from, "Error: User not found", {
                { name = "Type", value = "FeedError" },
                { name = "Success", value = "false" }
            })
        end
    end
)

-- Handler 7: Get Liked Posts
Handlers.add("get_liked_posts",
    function(msg)
        return msg.tags and msg.tags.Type == "GetLikedPosts"
    end,
    function(msg)
        local user_id = msg.from
        local page = tonumber(msg.tags.Page) or 1
        local limit = tonumber(msg.tags.Limit) or APP_CONFIG.max_posts_per_page
        
        if Users[user_id] then
            local liked_posts = {}
            local start_index = (page - 1) * limit + 1
            local end_index = start_index + limit - 1
            local current_index = 1
            
            -- Collect liked posts
            for like_key, like in pairs(Likes) do
                if like.user_id == user_id and Posts[like.post_id] then
                    if current_index >= start_index and current_index <= end_index then
                        local post = Posts[like.post_id]
                        local author = Users[post.author]
                        
                        table.insert(liked_posts, {
                            id = post.id,
                            title = post.title,
                            description = post.description,
                            image_url = post.image_url,
                            video_url = post.video_url,
                            author = {
                                id = post.author,
                                username = author and author.username or "Unknown",
                                avatar = author and author.profile.avatar or ""
                            },
                            created_at = post.created_at,
                            liked_at = like.liked_at,
                            likes_count = post.likes_count,
                            comments_count = post.comments_count,
                            modality = post.api_data and post.api_data.modality or "unknown"
                        })
                    end
                    current_index = current_index + 1
                end
            end
            
            -- Sort by like time (most recent first)
            table.sort(liked_posts, function(a, b) return a.liked_at > b.liked_at end)
            
            send_app_response(msg.from, "Liked Posts: " .. json.encode(liked_posts), {
                { name = "Type", value = "LikedPosts" },
                { name = "Success", value = "true" },
                { name = "Page", value = tostring(page) },
                { name = "PostCount", value = tostring(#liked_posts) }
            })
            
            log_app_event("LIKED_POSTS_REQUESTED", "User: " .. user_id)
        else
            send_app_response(msg.from, "Error: User not found", {
                { name = "Type", value = "LikedPostsError" },
                { name = "Success", value = "false" }
            })
        end
    end
)

-- Handler 8: App Analytics
Handlers.add("app_analytics",
    function(msg)
        return msg.tags and msg.tags.Type == "AppAnalytics"
    end,
    function(msg)
        local analytics = {
            app_info = {
                name = Name,
                version = Version,
                uptime = os.time() - Created,
                process_id = id
            },
            user_stats = Analytics,
            current_counts = {
                active_users = 0,
                active_posts = 0,
                active_likes = 0,
                active_follows = 0
            },
            content_breakdown = {
                video_posts = 0,
                image_posts = 0,
                text_posts = 0,
                api_posts = 0,
                local_posts = 0
            },
            relay_config = APP_CONFIG
        }
        
        -- Count current active items
        for _ in pairs(Users) do
            analytics.current_counts.active_users = analytics.current_counts.active_users + 1
        end
        for _, post in pairs(Posts) do
            analytics.current_counts.active_posts = analytics.current_counts.active_posts + 1
            
            -- Count by content type
            if post.api_data then
                analytics.content_breakdown.api_posts = analytics.content_breakdown.api_posts + 1
                if post.api_data.modality == "video" then
                    analytics.content_breakdown.video_posts = analytics.content_breakdown.video_posts + 1
                elseif post.api_data.modality == "image" then
                    analytics.content_breakdown.image_posts = analytics.content_breakdown.image_posts + 1
                elseif post.api_data.modality == "text" then
                    analytics.content_breakdown.text_posts = analytics.content_breakdown.text_posts + 1
                end
            else
                analytics.content_breakdown.local_posts = analytics.content_breakdown.local_posts + 1
            end
        end
        for _ in pairs(Likes) do
            analytics.current_counts.active_likes = analytics.current_counts.active_likes + 1
        end
        for _ in pairs(Follows) do
            analytics.current_counts.active_follows = analytics.current_counts.active_follows + 1
        end
        
        send_app_response(msg.from, "App Analytics: " .. json.encode(analytics), {
            { name = "Type", value = "AppAnalytics" },
            { name = "Success", value = "true" },
            { name = "Timestamp", value = tostring(os.time()) }
        })
        
        log_app_event("ANALYTICS_REQUESTED", "Analytics generated")
    end
)

-- Initialize Pinterest-like App
print("🚀 Pinterest-like App (HyperAOS) initialized!")
print("Process ID:", id)
print("Owner:", owner)
print("Version:", Version)
print("Relay Device:", APP_CONFIG.relay_device)
print("API Gateway:", APP_CONFIG.api_gateway)
print("")
print("📋 Available Pinterest App Handlers:")
print("- user_registration: Register users with wallet addresses")
print("- create_post: Create posts with external API integration")
print("- like_post: Like/unlike posts")
print("- process_api_response: Process external API responses")
print("- search_external_content: Search external content via API")
print("- get_feed: Get doom scrolling feed")
print("- get_liked_posts: Get user's liked posts")
print("- app_analytics: Get app analytics and statistics")
print("")
print("💡 Pinterest-like app is ready for social media doom scrolling!")

-- Send initialization message
send({
    target = owner,
    data = "🎉 Pinterest-like App (HyperAOS) is ready! Start creating posts, liking content, and doom scrolling!",
    tags = {
        { name = "Type", value = "PinterestAppInit" },
        { name = "ProcessId", value = id },
        { name = "Version", value = Version },
        { name = "RelayDevice", value = APP_CONFIG.relay_device },
        { name = "HandlerCount", value = "8" },
        { name = "Timestamp", value = tostring(os.time()) }
    }
})
