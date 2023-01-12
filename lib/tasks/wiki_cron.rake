# frozen_string_literal: true

namespace :update_wiki_users do
  desc "Update users for from the wiki to match ours"
  task run: :environment do
    # Setting up client
    client =
      Graphlient::Client.new(
        "https://wiki-server.makerepo.com/graphql",
        headers: {
          "Authorization" =>
            "Bearer #{Rails.application.credentials[Rails.env.to_sym][:wiki][:api_key]}"
        }
      )

    # Queries and mutations
    user_query = <<~GRAPHQL
      query($group: Int!) {
        groups {
          single(id: $group) {
            users {
              id
              name
              email
            }
          }
        }
      }
    GRAPHQL

    user_update_mutation = <<-GRAPHQL
          mutation($id: Int!, $groups: [Int]) {
            users {
              update(id: $id, groups: $groups) {
                responseResult {
                  succeeded
                }
              }
            }
          }
    GRAPHQL

    [
      { group: 1, name: "Administrators", downgrade_target: [2] },
      { group: 2, name: "Guests", downgrade_target: [1] }
    ].each do |group|
      puts("Querying #{group[:name]}...")
      # Querying the list of users
      response = client.query(user_query, { group: group[:group] })
      email_list = response.data.groups.single.users

      # List of failed emails
      error_emails = []

      # Looping through list to remove/add admin powers
      email_list.each do |u|
        user = User.find_by(email: u.email)
        if (group[:group] == 1 && (!user.present? || !user.staff?)) ||
             (group[:group] == 2 && user.present? && user.staff?)
          downgrade_user_response =
            client.query(
              user_update_mutation,
              { id: u.id, groups: group[:downgrade_target] }
            )
          unless downgrade_user_response
                   .data
                   .users
                   .update
                   .response_result
                   .succeeded == true
            error_emails << u.email
          end
        end
      end

      # Printing all failed users emails
      if error_emails.size > 0
        puts("The following emails have failed their change of group...")
        puts(error_emails)
      end
    end

    puts("Done!")
  end
end
