require "test_helper"

class WithdrawalsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @withdrawal = withdrawals(:one)
  end

  test "should get index" do
    get withdrawals_url
    assert_response :success
  end

  test "should get new" do
    get new_withdrawal_url
    assert_response :success
  end

  test "should create withdrawal" do
    assert_difference("Withdrawal.count") do
      post withdrawals_url, params: { withdrawal: { amount: @withdrawal.amount, pix_key: @withdrawal.pix_key, status: @withdrawal.status, user_id: @withdrawal.user_id } }
    end

    assert_redirected_to withdrawal_url(Withdrawal.last)
  end

  test "should show withdrawal" do
    get withdrawal_url(@withdrawal)
    assert_response :success
  end

  test "should get edit" do
    get edit_withdrawal_url(@withdrawal)
    assert_response :success
  end

  test "should update withdrawal" do
    patch withdrawal_url(@withdrawal), params: { withdrawal: { amount: @withdrawal.amount, pix_key: @withdrawal.pix_key, status: @withdrawal.status, user_id: @withdrawal.user_id } }
    assert_redirected_to withdrawal_url(@withdrawal)
  end

  test "should destroy withdrawal" do
    assert_difference("Withdrawal.count", -1) do
      delete withdrawal_url(@withdrawal)
    end

    assert_redirected_to withdrawals_url
  end
end
