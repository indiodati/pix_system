require "application_system_test_case"

class PixTransactionsTest < ApplicationSystemTestCase
  setup do
    @pix_transaction = pix_transactions(:one)
  end

  test "visiting the index" do
    visit pix_transactions_url
    assert_selector "h1", text: "Pix transactions"
  end

  test "should create pix transaction" do
    visit pix_transactions_url
    click_on "New pix transaction"

    fill_in "Amount", with: @pix_transaction.amount
    fill_in "Description", with: @pix_transaction.description
    fill_in "Pix key", with: @pix_transaction.pix_key
    fill_in "Status", with: @pix_transaction.status
    fill_in "Transaction type", with: @pix_transaction.transaction_type
    fill_in "User", with: @pix_transaction.user_id
    click_on "Create Pix transaction"

    assert_text "Pix transaction was successfully created"
    click_on "Back"
  end

  test "should update Pix transaction" do
    visit pix_transaction_url(@pix_transaction)
    click_on "Edit this pix transaction", match: :first

    fill_in "Amount", with: @pix_transaction.amount
    fill_in "Description", with: @pix_transaction.description
    fill_in "Pix key", with: @pix_transaction.pix_key
    fill_in "Status", with: @pix_transaction.status
    fill_in "Transaction type", with: @pix_transaction.transaction_type
    fill_in "User", with: @pix_transaction.user_id
    click_on "Update Pix transaction"

    assert_text "Pix transaction was successfully updated"
    click_on "Back"
  end

  test "should destroy Pix transaction" do
    visit pix_transaction_url(@pix_transaction)
    accept_confirm { click_on "Destroy this pix transaction", match: :first }

    assert_text "Pix transaction was successfully destroyed"
  end
end
