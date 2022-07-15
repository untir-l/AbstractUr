# This file is part of AbstractUr, an implementation of the basic rules of the
# Game of Ur (https://en.wikipedia.org/wiki/Royal_Game_of_Ur).
# Copyright © 2022-present Arjun Satarkar

# AbstractUr is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License version 3,
# a copy of which is included in the file `LICENSE.txt`.

# AbstractUr is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License version 3 for more details.

# You should have received a copy of the GNU Affero General Public License
# version 3 along with this program.  If not, see
# <https://www.gnu.org/licenses/>.

defmodule AbstractUr do
  @moduledoc """
  A game of Ur.
  """
  @type player_id :: integer
  @type square_id :: integer
  @type square :: %{
          rosette?: boolean,
          direction_for: %{player_id => cardinal_direction},
          neighbours: %{cardinal_direction => square_id | nil},
          piece_owner: player_id | nil
        }
  @type cardinal_direction :: :north | :south | :east | :west
  @type move :: %{
          initial_square_id: square_id | nil,
          roll: non_neg_integer()
        }
  @type state :: %{
          squares: %{square_id => square},
          first_square_for: %{player_id => square_id},
          last_square_for: %{player_id => square_id},
          waiting_piece_num: %{player_id => non_neg_integer},
          passed_piece_num: %{player_id => non_neg_integer},
          total_piece_per_player_num: pos_integer(),
          turn_after: %{player_id => player_id},
          current_player: player_id,
          winner: player_id | nil
        }

  @spec traverse(state(), move()) :: {:ok, square_id | nil} | :error
  defp traverse(_, %{initial_square_id: final_square_id, roll: 0}) do
    # No more squares left to move, so we have reached our destination
    {:ok, final_square_id}
  end

  defp traverse(state, move) do
    initial_square = state.squares[move.initial_square_id]

    case initial_square.neighbours[initial_square.direction_for[state.current_player]] do
      nil ->
        # There is no next square
        if move.initial_square_id == state.last_square_for[state.current_player] and
             move.roll == 1 do
          # This piece got off the board
          {:ok, nil}
        else
          # This move is invalid, likely because the piece would overshoot the end
          :error
        end

      next_square ->
        # There is a next square, so continue traversal
        traverse(state, %{initial_square_id: next_square, roll: move.roll - 1})
    end
  end

  @spec initial_position_valid?(state(), square_id()) :: boolean()
  defp initial_position_valid?(state, initial_square_id) do
    if initial_square_id do
      # We are moving from a square on the board
      state.squares[initial_square_id].piece_owner == state.current_player
    else
      # We are moving from off the board
      state.waiting_piece_num[state.current_player] > 0
    end
  end

  @spec final_position_valid?(state(), square_id | nil) :: boolean
  defp final_position_valid?(state, final_position) do
    if final_position do
      final_position.piece_owner != state.current_player and
        !(final_position.piece_owner && final_position.rosette?)
    else
      # The piece is moving off the board - nothing can be invalid
      true
    end
  end

  @doc """
  Apply a move to state, producing an updated state. If the move is invalid in
  any way then `:error` is returned.
  """
  @spec make_move(state(), move()) :: {:ok, state()} | :error
  def make_move(state, move) do
    if initial_position_valid?(state, move.initial_square_id) do
      # The initial position (which we move *from*) is valid for this move
      case traverse(state, move) do
        {:ok, final_position} ->
          # Traversal successfully found a final position
          if final_position_valid?(state, final_position) do
            # The final position (which we move *to*) is valid for this move
            {:ok, make_move(state, move.initial_square_id, final_position)}
          else
            # The final position isn't valid to move to in this case
            :error
          end

        :error ->
          # Traversal failed - likely because the move would overshoot the board
          :error
      end
    else
      # The initial position isn't valid to move from in this case
      :error
    end
  end

  @spec make_move(state(), square_id() | nil, square_id() | nil) :: state()
  defp make_move(state, initial_position, final_position) do
    # Remove piece from initial position
    state =
      if initial_position do
        # We are moving from a square - remove the piece from there
        put_in(state, [:squares, initial_position], nil)
      else
        # We are moving from off the board - remove a piece from there
        put_in(
          state,
          [:waiting_piece_num, state.current_player],
          state.waiting_piece_num[state.current_player] - 1
        )
      end

    # If final position has a piece already, exile it back to waiting off-board
    state =
      if final_position && state.squares[final_position].piece_owner do
        put_in(
          put_in(state, [:squares, final_position, :piece_owner], nil),
          [:waiting_piece_num, state.squares[final_position].piece_owner],
          state.waiting_piece_num[state.squares[final_position].piece_owner] + 1
        )
      end

    # Put the moved piece on the final position
    state =
      if final_position do
        put_in(state, [:squares, final_position, :piece_owner], state.current_player)
      else
        put_in(
          state,
          [:passed_piece_num, state.current_player],
          state.passed_piece_num[state.current_player] + 1
        )
      end

    # If anyone has won, reflect that
    state =
      if state.passed_piece_num[state.current_player] ==
           state.total_piece_per_player_num do
        %{state | winner: state.current_player}
      end

    # Update current player if needed
    state =
      if final_position do
        if state.squares[final_position].rosette? do
          state
        else
          %{state | current_player: state.turn_after[state.current_player]}
        end
      else
        state
      end

    state
  end
end
