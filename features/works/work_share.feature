# We need to load the site skin to make the share modal work properly:
@works @load-default-skin
Feature: Share Works
  Testing the "Share" button on works, with Javascript emulation

  @javascript
  Scenario: Share a work
    Given the work "Blabla" by "testuser1" with fandom "Stargate SG-1"
      And I am logged in as "testuser1"
    When I view the work "Blabla"
    Then I should see "Share"
    When I follow "Share"
    Then I should see "Copy and paste the following code to link back to this work" within "#share"
      And I should see "or use the Tweet or Tumblr links to share the work" within "#share"
      And I should see '<strong>Blabla</strong></a> (8 words)' within "#share textarea"
      And I should see 'by <a href="http://www.example.com/users/testuser1"><strong>testuser1</strong></a>' within "#share textarea"
      And I should see 'Fandom: <a href="http://www.example.com/tags/Stargate%20SG-1">Stargate SG-1</a>' within "#share textarea"
      And I should see "Rating: Not Rated" within "#share textarea"
      And I should see "Warnings: No Archive Warnings Apply" within "#share textarea"
      And the share modal should contain social share buttons
      And I should not see "Series:" within "#share textarea"
      And I should not see "Relationships:" within "#share textarea"
      And I should not see "Characters:" within "#share textarea"
      And I should not see "Summary:" within "#share textarea"
    When I view the work "Blabla"
      And I log out
    Then I should see "Share"
    When I follow "Share"
    Then I should see "Copy and paste the following code to link back to this work" within "#share"
      And I should see "or use the Tweet or Tumblr links to share the work" within "#share"
      And I should see '<strong>Blabla</strong></a> (8 words)' within "#share textarea"
      And I should see 'by <a href="http://www.example.com/users/testuser1"><strong>testuser1</strong></a>' within "#share textarea"
      And I should see 'Fandom: <a href="http://www.example.com/tags/Stargate%20SG-1">Stargate SG-1</a>' within "#share textarea"
      And I should see "Rating: Not Rated" within "#share textarea"
      And I should see "Warnings: No Archive Warnings Apply" within "#share textarea"
      And the share modal should contain social share buttons
      And I should not see "Series:" within "#share textarea"
      And I should not see "Relationships:" within "#share textarea"
      And I should not see "Characters:" within "#share textarea"
      And I should not see "Summary:" within "#share textarea"

  Scenario: Share option should be disabled if all creators have set the option to disable sharing on their works
  
  Given I am logged in as "PrivaC"
    And I set my preferences to hide the share buttons on my work
    And the work "Don't Lie When You're Hurting Inside" by "PrivaC"
    And the user "EitherWay" allows co-creators
  When I view the work "Don't Lie When You're Hurting Inside"
  Then I should not see "Share"
  When I add the co-author "EitherWay" to the work "Don't Lie When You're Hurting Inside"
    And I view the work "Don't Lie When You're Hurting Inside"
  Then I should see "Share"
  When I am logged in as "EitherWay"
    And I set my preferences to hide the share buttons on my work
    And I view the work "Don't Lie When You're Hurting Inside"
  Then I should not see "Share"

  @javascript
  Scenario: Sharing should work for multi-chapter works
    Given the chaptered work "Whatever"
    When I view the work "Whatever"
    Then I should see "Share"
    When I follow "Share"
    Then I should see "Copy and paste the following code to link back to this work"
      And I should see "><strong>Whatever</strong></a> (10 words) b" within "#share textarea"

  @javascript
  Scenario: Share URL should not be used for post-login redirect
    Given I have a work "Blabla"
      And the following activated user exists
      | login   | password |
      | MadUser | password |
    When I am a visitor
      And I view the work "Blabla"
    Then I should see "Share"
    When I follow "Share"
    Then I should see "Close" within "#modal"
    When I follow "Close"
      And I follow "Log In"
      And I fill in "Username or email:" with "maduser"
      And I fill in "Password:" with "password"
      And I press "Log In"
    Then the url should not include "share"
      # Shown when the share url is accessed directly
      And I should not see "Sorry, you need to have JavaScript enabled for this."
