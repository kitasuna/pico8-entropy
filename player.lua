function new_player(sprite_num, pos_x, pos_y, size_x, size_y)
  local player = new_sprite(
  sprite_num,
  pos_x,
  pos_y,
  size_x,
  size_y
  )

  local velocity_max = 1.0
  local slide_step_down = 0.035

  player.state = PLAYER_STATE_GROUNDED
  player.deaths = 0
  player.score = 0
  player.vel_x = 0
  player.vel_y = 0
  player.invincible = false
  player.frame_base = 1
  player.frame_offset = 0
  player.frame_step = 0
  player.facing = DIRECTION_DOWN
  player.can_travel = (1 << FLAG_FLOOR)
  player.map_offset_x = 0
  player.map_offset_y = 0

  player.frames_walking = {
    { anim={7, 8, 7, 9}, flip=false },
    { anim={4, 5, 4, 6}, flip=false },
    { anim={1, 2, 1, 3}, flip=false },
    { anim={4, 5, 4, 6}, flip=true }
  }

  player.frames_zapped = { 16, 17, 18, 16, 17, 18, 16, 17, 18 }

  -- API, allows other entities to check on player
  player.is_dead = function()
    if player.state == PLAYER_STATE_DEAD_ZAPPED or
      player.state == PLAYER_STATE_DEAD_FALLING then
      return true
    end

    return false
  end

  player.reset = function(l)
    player.frame_base = 1
    player.frame_offset = 1
    player.facing = DIRECTION_DOWN
    player.can_travel = (1 << FLAG_FLOOR)
    player.state = PLAYER_STATE_GROUNDED
    player.vel_x = 0
    player.vel_y = 0
    player.pos_x = l.player_pos_x
    player.pos_y = l.player_pos_y
  end

  player.handle_proj_player_collision = function(name, payload)
    if player.state == PLAYER_STATE_FLOATING then
      sc_sliding(player)
    end
  end

  player.handle_player_item_collision = function(name, payload)
      player.score += 1
  end

  player.handle_beam_player_collision = function(name, payload)
      player.deaths += 1
      player.can_move_x = false
      player.can_move_y = false
      player.vel_x = 0
      player.vel_y = 0
      player.state = PLAYER_STATE_DEAD_ZAPPED
      player.frame_step = 0
      player.frame_offset = 0
  end

  player.handle_proj_expiration = function(name, payload)
    if player.state == PLAYER_STATE_FLOATING then
      sc_sliding(player) 
    end
  end

  player.handle_entity_reaches_target = function(name, payload)
    player.state = PLAYER_STATE_HOLDING
  end

  player.handle_level_init = function(name, payload)
    -- TODO: We probably want more happening in here, like position etc
    player.map_offset_x = payload.map_offset_x
    player.map_offset_y = payload.map_offset_y - 4 -- cheat a little here
  end

  player.handle_button = function(name, payload)
    -- If they're sliding, they can't do much
    if player.state == PLAYER_STATE_SLIDING then
      return
    end

    -- If they're dying, disable input
    if player.state == PLAYER_STATE_DEAD_FALLING or player.state == PLAYER_STATE_DEAD_ZAPPED then
      return
    end

    -- If they're floating and the press isn't a float toggle, return
    if player.state == PLAYER_STATE_FLOATING and (payload.input_mask & (1 << BTN_X) == 0) then
      return
    end

    -- If they're floating and the press IS a float toggle, ground them and return
    if player.state == PLAYER_STATE_FLOATING and (payload.input_mask & (1 << BTN_X) > 0) then
        sc_sliding(player)
        return
    end

    -- If they're holding, all they can do is change the facing or release holding
    if player.state == PLAYER_STATE_HOLDING then
      if payload.input_mask & (1 << BTN_O) == 0 then
        player.state = PLAYER_STATE_GROUNDED 
        return
      end

      local new_facing = player.facing
      if payload.input_mask & (1 << BTN_U) > 0 then
        new_facing = DIRECTION_UP
      end

      if payload.input_mask & (1 << BTN_D) > 0 then
        new_facing = DIRECTION_DOWN
      end

      if payload.input_mask & (1 << BTN_L) > 0 then
        new_facing = DIRECTION_LEFT
      end

      if payload.input_mask & (1 << BTN_R) > 0 then
        new_facing = DIRECTION_RIGHT
      end

      local rotation = resolve_rotation(player.facing, new_facing)
      if rotation != "ROTATION_0" then
        -- event
        qm.ae("PLAYER_ROTATION", {rotation=rotation, pos_x=get_center_x(player), pos_y=get_center_y(player)})
      end
      player.facing = new_facing
      return
    end

    -- If they're grounded, there's a projectile, and the press is a float toggle, make them float!
    if (payload.input_mask & (1 << BTN_X) > 0) and (payload.projectile != nil) and (player.state == PLAYER_STATE_GROUNDED) then
        player.state = PLAYER_STATE_FLOATING
        player.can_travel = (1 << FLAG_FLOOR) | (1 << FLAG_GAP)
        local grav_result = calc_cheat_grav(
        {x=player.pos_x, y=player.pos_y},
        {x=payload.projectile.pos_x, y=payload.projectile.pos_y},
        1.0,
        128.0
        )

        player.vel_x = grav_result.vel.x
        player.vel_y = grav_result.vel.y

        return
    end

    -- Try returning if grav button is being held down
    if payload.input_mask & (1 << BTN_O) > 0 then
      player.vel_x = 0
      player.vel_y = 0
      return
    end


    -- Up
    if payload.input_mask & (1 << BTN_U) > 0 then
      player.facing = DIRECTION_UP
      player.vel_y = -velocity_max
    -- Down
    elseif payload.input_mask & (1 << BTN_D) > 0 then
      player.facing = DIRECTION_DOWN
      player.vel_y = velocity_max
    end

    if payload.input_mask & (1 << BTN_U) == 0 and
      payload.input_mask & (1 << BTN_D) == 0 then
      player.vel_y = 0
    end

    if payload.input_mask & (1 << BTN_L) > 0 then
      player.facing = DIRECTION_LEFT
      player.vel_x = -velocity_max
    elseif payload.input_mask & (1 << BTN_R) > 0 then
      player.facing = DIRECTION_RIGHT
      player.vel_x = velocity_max
    end

    if payload.input_mask & (1 << BTN_L) == 0 and
      payload.input_mask & (1 << BTN_R) == 0 then
      player.vel_x = 0
    end

    if player.facing == DIRECTION_DOWN then
      player.frame_base = 1
    elseif player.facing == DIRECTION_UP then
      player.frame_base = 9
    elseif player.facing == DIRECTION_RIGHT then
      player.frame_base = 5
    elseif player.facing == DIRECTION_LEFT then
      player.frame_base = 5
    end

    if payload.input_mask > 0 then
      player.frame_step += 1
      if player.frame_step > 6 then
        player.frame_offset += 1
        player.frame_step = 0
        if player.frame_offset > 3 then
          player.frame_offset = 0
        end
      end
    end
  end

  player.draw = function()
    if player.state == PLAYER_STATE_GROUNDED or player.state == PLAYER_STATE_HOLDING then
      -- spr(player.frame_base + player.frame_offset, player.pos_x, player.pos_y, 1.0, 1.0, player.flip_x, player.flip_y)
      local frames = player.frames_walking[player.facing + 1]
      spr(frames.anim[player.frame_offset + 1],player.pos_x, player.pos_y, 1.0, 1.0, frames.flip, false)
    elseif player.state == PLAYER_STATE_FLOATING then
      spr(10, player.pos_x, player.pos_y, 1.0, 1.0, false, false)
    elseif player.state == PLAYER_STATE_SLIDING then
      spr(12 + player.facing, player.pos_x, player.pos_y, 1.0, 1.0, false, false)
    elseif player.state == PLAYER_STATE_DEAD_FALLING then
      sspr(88, 0, 8, 8, player.pos_x + (player.frame_offset * 2), player.pos_y + (player.frame_offset * 2), 8 \ (player.frame_offset + 1), 8 \ (player.frame_offset + 1))
    elseif player.state == PLAYER_STATE_DEAD_ZAPPED then
      local frames = player.frames_zapped
      spr(frames[player.frame_offset + 1],player.pos_x, player.pos_y, 1.0, 1.0, false, false)
    end
  end

  player.update = function(ent_man, level)
    local player_center_x = get_center_x(player)
    local player_center_y = get_center_y(player)

    local player_next_x = (player_center_x + player.vel_x) -- + (player.facing != 3 and 5 or 1)
    local player_next_y = player_center_y + player.vel_y -- + (player.facing == 2 and 7 or 0)
    local curr_map_x = ((player_center_x - player.map_offset_x) \ 8) + level.start_tile_x
    local next_map_x = ((player_next_x - player.map_offset_x) \ 8) + level.start_tile_x
    local curr_map_y = ((player_center_y - player.map_offset_y) \ 8) + level.start_tile_y
    local next_map_y = ((player_next_y - player.map_offset_y) \ 8) + level.start_tile_y
    local can_move_x = true
    local can_move_y = true

    if player.state == PLAYER_STATE_DEAD_FALLING then
      if player.frame_offset < 3 then
        player.frame_step += 1
        if player.frame_step > 20 then
          player.frame_offset += 1
          player.frame_step = 0
        end
      else
        qm.ae("PLAYER_DEATH", {level = level})
        return
      end
    end

    if player.state == PLAYER_STATE_DEAD_ZAPPED then
      if player.frame_offset < 9 then
        player.frame_step += 1
        if player.frame_step > 5 then
          player.frame_offset += 1
          player.frame_step = 0
        end
      else
        qm.ae("PLAYER_DEATH", {level = level})
        return
      end
    end

    -- if centered over a gap, and not floating, increment deaths (and probably trigger some event?)
    if fget(mget(curr_map_x, curr_map_y), FLAG_GAP) and (player.state != PLAYER_STATE_FLOATING and player.state != PLAYER_STATE_DEAD_FALLING) then
      player.deaths += 1
      player.can_move_x = false
      player.can_move_y = false
      player.vel_x = 0
      player.vel_y = 0
      player.state = PLAYER_STATE_DEAD_FALLING
      player.frame_step = 0
      player.frame_offset = 0
      return
    end

    if fget(mget(next_map_x, curr_map_y)) & player.can_travel == 0 then
      can_move_x = false
    end

    if fget(mget(curr_map_x, next_map_y)) & player.can_travel == 0 then
      can_move_y = false
    end

    if fget(mget(next_map_x, next_map_y)) & player.can_travel == 0 then
      can_move_x = false
      can_move_y = false
    end

    -- local curr_map_x = (get_center_x(player) - player.map_offset_x) \ 8
    -- local curr_map_y = (get_center_y(player) - player.map_offset_y) \ 8
    if fget(mget(curr_map_x, curr_map_y), FLAG_STAIRS) then
      -- printh("STAIRS!"..frame_counter)
      qm.ae("PLAYER_GOAL", {})
    end

    -- Make a hypothetical player sprite at the next location after update and check for collision
    local player_at_next = new_sprite(
      0, -- sprite num, doesn't matter
      player.pos_x+player.vel_x,
      player.pos_y+player.vel_y,
      player.size_x,
      player.size_y
    )
    for k, ent in pairs(ent_man.ents) do
      if fget(ent.num, FLAG_COLLIDES_PLAYER) == true then
        if collides(player_at_next, ent) then 
          can_move_x = false
          can_move_y = false
        end
      end
    end

    if can_move_x == true then
      player.pos_x += player.vel_x
    end

    if can_move_y == true then
      player.pos_y += player.vel_y
    end

    -- the slide, deceleration and stopping
    if player.state == PLAYER_STATE_SLIDING then
      if player.vel_x > 0 then
        player.vel_x -= slide_step_down
      elseif player.vel_x < 0 then
        player.vel_x += slide_step_down
      end

      if player.vel_y > 0 then
        player.vel_y -= slide_step_down
      elseif player.vel_y < 0 then
        player.vel_y += slide_step_down
      end

      if (player.vel_x <= slide_step_down and player.vel_x >= -slide_step_down) then
        player.vel_x = 0
      end
      if (player.vel_y <= slide_step_down and player.vel_y >= -slide_step_down) then
        player.vel_y = 0
      end

      if player.vel_x == 0 and player.vel_y == 0 and player.state == PLAYER_STATE_SLIDING then
        player.state = PLAYER_STATE_GROUNDED
      end
    end
  end

  return player
end

function sc_sliding(player)
    player.state = PLAYER_STATE_SLIDING
    player.can_travel = (1 << FLAG_FLOOR) | (1 << FLAG_GAP)
end

-- Given two facings, decide how much rotation we just did
function resolve_rotation(start_facing, end_facing)
  if start_facing == end_facing then
    return "ROTATION_0"
  elseif start_facing == DIRECTION_UP and end_facing == DIRECTION_DOWN then
    return "ROTATION_180_DOWN"
  elseif start_facing == DIRECTION_UP and end_facing == DIRECTION_LEFT then
    return "ROTATION_90_LEFT"
  elseif start_facing == DIRECTION_UP and end_facing == DIRECTION_RIGHT then
    return "ROTATION_90_RIGHT"
  elseif start_facing == DIRECTION_DOWN and end_facing == DIRECTION_UP then
    return "ROTATION_180_UP"
  elseif start_facing == DIRECTION_DOWN and end_facing == DIRECTION_RIGHT then
    return "ROTATION_90_LEFT"
  elseif start_facing == DIRECTION_DOWN and end_facing == DIRECTION_LEFT then
    return "ROTATION_90_RIGHT"
  elseif start_facing == DIRECTION_LEFT and end_facing == DIRECTION_RIGHT then
    return "ROTATION_180_RIGHT"
  elseif start_facing == DIRECTION_LEFT and end_facing == DIRECTION_DOWN then
    return "ROTATION_90_LEFT"
  elseif start_facing == DIRECTION_LEFT and end_facing == DIRECTION_UP then
    return "ROTATION_90_RIGHT"
  elseif start_facing == DIRECTION_RIGHT and end_facing == DIRECTION_UP then
    return "ROTATION_90_LEFT"
  elseif start_facing == DIRECTION_RIGHT and end_facing == DIRECTION_DOWN then
    return "ROTATION_90_RIGHT"
  elseif start_facing == DIRECTION_RIGHT and end_facing == DIRECTION_LEFT then
    return "ROTATION_180_LEFT"
  end
  return "ROTATION_UNKNOWN"
end

function get_center_x(sprite)
    return flr(sprite.pos_x + (sprite.size_x \ 2))
end

function get_center_y(sprite)
    return flr(sprite.pos_y + (sprite.size_y \ 2))
end
