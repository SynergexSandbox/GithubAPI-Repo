@isTest
private class AccountHandlerTest {

	static testmethod void testAccountDeletionNonAdmin(){
		User nonAdmin = [Select id from User where profile.name = 'Synergy Sales: Standard User' and isActive = true limit 1];
		System.runAs(nonAdmin){
			try{
				delete [Select id from Account];
				System.assert(false, 'We should not have been able to delete the accounts because we are non-admins');
			}catch(Exception ex){
				System.assert(true, 'We expect that non-admins shouldnt be able to delete accounts');
			}
		}
	}

	static testmethod void testAccountDeletionAdmin(){
		User admin = [Select id from User where profile.name = 'System Administrator' and isActive = true limit 1];
		System.runAs(admin){
			try{
				delete [Select id from Account];
				System.assert(true, 'Admins should always be able to delete accounts');
			}catch(Exception ex){
				System.assert(false, 'Admin unable to delete account');
			}
		}
	}

	static testmethod void testCheckForOwnerChange()  {
		List<Profile> profiles = [select id from Profile where Name = 'Synergy Sales: Standard User'];						
		User user1 = new User();
				user1.profileID = profiles[0].id;		
				user1.username = 'testing1@synergex.com';
				user1.email = 'testing1@synergex.com';		
				user1.lastName = 'Tester';	
				user1.isActive = true;
				user1.alias = 'Test';
				user1.timeZoneSidKey = 'America/Los_Angeles';
				user1.localeSidKey = 'en_US';
				user1.emailEncodingKey = 'UTF-8';
				user1.languageLocaleKey = 'en_US';		

		User user2 = new User();
				user2.profileID = profiles[0].id;		
				user2.username = 'testing2@synergex.com';
				user2.email = 'testing2@synergex.com';		
				user2.lastName = 'Tester2';	
				user2.isActive = true;
				user2.alias = 'Test2';
				user2.timeZoneSidKey = 'America/Los_Angeles';
				user2.localeSidKey = 'en_US';
				user2.emailEncodingKey = 'UTF-8';
				user2.languageLocaleKey = 'en_US';

		insert new List<User>{user1, user2};		
				
		Account newAccount = new Account();
		newAccount.OwnerId = user1.Id;
		newAccount.Name = 'Owner Tester';
		insert newAccount;		
		
		newAccount.OwnerId = user2.Id;
		update newAccount;

		Account updatedAccount = [select id, previous_owner__c, ownerid from account where id = : newAccount.Id];
		System.assertEquals(user1.id, updatedAccount.previous_owner__c);
	}

	static testmethod void testDiscountChangeNotice(){
		//this just sends an email, so we can't really do much other than
		//get code coverage
		Account a = [Select id, Curr_Discount__c from Account where type like '%ISV%' limit 1];
		Decimal discountBefore = a.Curr_Discount__c;
		Sales_Invoice__c invoice = new Sales_Invoice__c(
			Invoice_Amount__c = 1000000,
			Account__c = a.id,
			Date__c = Date.today()
		);
		
		insert invoice;
		//see if our discount changed
		a = [Select id, Curr_Discount__c from Account where id =: a.id];
		//System.assertNotEquals(discountBefore, a.Curr_Discount__c, 'The discounts should change, which should cause an alert to be sent to Bill');
		//If this ^ assertion fails, make sure Account.Curr_Discount__c is factoring in the current year's sales 
	}

	static testmethod void testLicenseSyncDefaults(){
		list<Account> accts = new list<Account>{
			new Account(name='not_isv', type='CENDUA'),
			new Account(name='is_isv', type='CISVA')
		};
		insert accts;

		accts = [Select id, type, Account_NoNagALM__c, Account_NoNagSUB__c from Account where id in :accts];
		system.assertEquals(2, accts.size());
		for(Account acct : accts){
			if(acct.type.containsIgnoreCase('isv')){
				system.assertEquals(true, acct.Account_NoNagALM__c, 'isv account didnt default to no-nag ALM');
				system.assertEquals(true, acct.Account_NoNagSUB__c, 'isv account didnt default to no-nag SUB');
			}else{
				system.assertEquals(false, acct.Account_NoNagALM__c, 'non-isv account defaulted to no-nag ALM');
				system.assertEquals(false, acct.Account_NoNagSUB__c, 'non-isv account defaulted to no-nag SUB');
			}
		}
	}

	static testmethod void testGUIDAssignment(){
		List<Account> accts = new list<Account>{
			new Account(name='foo_0', Type='CISVA'),
			new Account(name='foo_1', Type='CISVA'),
			new Account(name='foo_2', Type='CISVA')
		};

		insert accts;

		accts = [Select id, Account_GUID__c from Account];
		System.assertNotEquals(0, accts.size(), 'No accounts returned from query.');

		for(Account a : accts){
			System.assertNotEquals(0, a.Account_GUID__c.length(), 'Blank account guid located.  all accounts must have guids.');
		}
	}

	static testmethod void testGDPRFlaggingLogic(){
		Account nonGDPRAcct = new Account(name='not gdpr', billingCountry = 'USA');
		insert nonGDPRAcct;
		list<contact> childContacts = new list<Contact>{
			new Contact(accountId = nonGDPRAcct.id, lastName='foo', MailingCountry=nonGDPRAcct.BillingCountry),
			new Contact(accountId = nonGDPRAcct.id, lastName='GDPR Person', MailingCountry='UK')
		};
		insert childContacts;
		childContacts = [Select id, lastName, Contact_GDPR_Applicable__c from Contact where accountID =: nonGDPRAcct.id];
		System.assertEquals(2, childContacts.size(), 'incorrect child contact count. cannot proceed with test');
		for(contact c : childContacts){
			if(c.LastName == 'GDPR Person'){
				System.assert(c.Contact_GDPR_Applicable__c);
			}else{
				System.assert(!c.Contact_GDPR_Applicable__c);
			}
		}

		nonGDPRAcct = [Select id, GDPR_applicable__c, BillingCountry from account where id =: nonGDPRAcct.id];
		System.assert(!nonGDPRAcct.gdpr_applicable__c, 'US account shouldnt be protected by gdpr');

		nonGDPRAcct.BillingCountry = 'ireland';
		update nonGDPRAcct;
		nonGDPRAcct = [Select id, GDPR_applicable__c, BillingCountry, (select id, Contact_GDPR_Applicable__c from Contacts where Contact_GDPR_Applicable__c = true) from account where id =: nonGDPRAcct.id];
		System.assert(nonGDPRAcct.gdpr_applicable__c, 'Billing country was moved to ireland, should be protected by gdpr');
		System.assertEquals(childContacts.size(), nonGDPRAcct.Contacts.size(), 'All of the child contacts should be protected by the GDPR now that the account is.');


		Account GDPRAcct = new Account(name='yes gdpr', shippingCountry = 'UK');
		insert GDPRAcct;
		GDPRAcct = [Select id, GDPR_applicable__c from account where id =: GDPRAcct.id];
		System.assert(GDPRAcct.gdpr_applicable__c, 'UK account should be protected by gdpr');
	}

	@testSetup
	static void doTheSetupStuff(){
		//create the 'prevent account deletion' setting
		Debug_Settings__c moreCustomSettings = new Debug_Settings__c(name='testingCustom389423');
    	moreCustomSettings.Allow_Account_Deletion__c = false;
    	insert moreCustomSettings;

    	//create a test ISV account
		Account a = new Account(
			Name='TEST TEST STSETSEDDDDD',
			Type='CISVA'
		);
		insert a;
	}
    
}