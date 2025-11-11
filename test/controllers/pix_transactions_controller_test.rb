require "test_helper"

class PixTransactionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @pix_transaction = pix_transactions(:one)
  end

  test "should get index" do
    get pix_transactions_url
    assert_response :success
  end

  test "should get new" do
    get new_pix_transaction_url
    assert_response :success
  end

  test "should create pix_transaction" do
    assert_difference("PixTransaction.count") do
      post pix_transactions_url, params: { pix_transaction: { amount: @pix_transaction.amount, description: @pix_transaction.description, pix_key: @pix_transaction.pix_key, status: @pix_transaction.status, transaction_type: @pix_transaction.transaction_type, user_id: @pix_transaction.user_id } }
    end

    assert_redirected_to pix_transaction_url(PixTransaction.last)
  end

  test "should show pix_transaction" do
    get pix_transaction_url(@pix_transaction)
    assert_response :success
  end

  test "should get edit" do
    get edit_pix_transaction_url(@pix_transaction)
    assert_response :success
  end

  test "should update pix_transaction" do
    patch pix_transaction_url(@pix_transaction), params: { pix_transaction: { amount: @pix_transaction.amount, description: @pix_transaction.description, pix_key: @pix_transaction.pix_key, status: @pix_transaction.status, transaction_type: @pix_transaction.transaction_type, user_id: @pix_transaction.user_id } }
    assert_redirected_to pix_transaction_url(@pix_transaction)
  end

  test "should destroy pix_transaction" do
    assert_difference("PixTransaction.count", -1) do
      delete pix_transaction_url(@pix_transaction)
    end

    assert_redirected_to pix_transactions_url
  end
end
