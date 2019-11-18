
var Test = require('../config/testConfig.js');
var BigNumber = require('bignumber.js');

contract('Flight Surety Tests', async (accounts) => {

  var config;
  before('setup contract', async () => {
    config = await Test.Config(accounts);

    await config.flightSuretyData.authorizeCaller(config.flightSuretyApp.address);
  });

  /****************************************************************************************/
  /* Operations and Settings                                                              */
  /****************************************************************************************/

  it(`(multiparty) has correct initial isOperational() value`, async function () {

    // Get operating status
    let status = await config.flightSuretyData.isOperational.call();
    assert.equal(status, true, "Incorrect initial operating status value");

  });

  it(`(multiparty) can block access to setOperatingStatus() for non-Contract Owner account`, async function () {

      // Ensure that access is denied for non-Contract Owner account
      let accessDenied = false;
      try 
      {
          await config.flightSuretyData.setOperatingStatus(false, { from: config.testAddresses[2] });
      }
      catch(e) {
          accessDenied = true;
      }
      assert.equal(accessDenied, true, "Access not restricted to Contract Owner");
            
  });

  it(`(multiparty) can allow access to setOperatingStatus() for Contract Owner account`, async function () {

      // Ensure that access is allowed for Contract Owner account
      let accessDenied = false;
      try 
      {
          await config.flightSuretyData.setOperatingStatus(false);
      }
      catch(e) {
          accessDenied = true;
      }
      assert.equal(accessDenied, false, "Access not restricted to Contract Owner");
      
  });

  it(`(multiparty) can block access to functions using requireIsOperational when operating status is false`, async function () {

      await config.flightSuretyData.setOperatingStatus(false);

      let reverted = false;
      let newAirline = accounts[2];

      try 
      {
        await config.flightSuretyApp.registerAirline(newAirline, {from: config.firstAirline});
      }
      catch(e) {
          reverted = true;
      }
      assert.equal(reverted, true, "Access not blocked for requireIsOperational");      

      // Set it back for other tests to work
      await config.flightSuretyData.setOperatingStatus(true);

  });

  it('(airline) cannot register an Airline using registerAirline() if it is not funded', async () => {
    
    // ARRANGE
    let currentAirline = accounts[1];
    let newAirline = accounts[2];

    // ACT
    try {
        await config.flightSuretyApp.registerAirline(newAirline, {from: currentAirline});
    }
    catch(e) {

    }
    let result = await config.flightSuretyData.isAirlineRegistered.call(newAirline); 

    // ASSERT
    assert.equal(result, false, "Airline should not be able to register another airline if it hasn't provided funding");

  });
 

  it('(airline) register an Airline using registerAirline() without consensus', async () => {
    // check if none is registered, and register
    let newAirline = accounts[1];
    let result = await config.flightSuretyData.isAirlineRegistered.call(newAirline); 
    assert.equal(result, false, "Airline should not be registered");
    await config.flightSuretyApp.registerAirline(newAirline, {from: config.firstAirline});

    newAirline = accounts[2];
    result = await config.flightSuretyData.isAirlineRegistered.call(newAirline); 
    assert.equal(result, false, "Airline should not be registered");
    await config.flightSuretyApp.registerAirline(newAirline, {from: config.firstAirline});

    newAirline = accounts[3];
    result = await config.flightSuretyData.isAirlineRegistered.call(newAirline); 
    assert.equal(result, false, "Airline should not be registered");
    await config.flightSuretyApp.registerAirline(newAirline, {from: config.firstAirline});

    newAirline = accounts[4];
    result = await config.flightSuretyData.isAirlineRegistered.call(newAirline); 
    assert.equal(result, false, "Airline should not be registered");
    await config.flightSuretyApp.registerAirline(newAirline, {from: config.firstAirline});
    
    // just the first 3 accs should be registered without consensus
    result = await config.flightSuretyData.isAirlineRegistered.call(accounts[1]);
    assert.equal(result, true, "Airline acc 1 should be registered");

    result = await config.flightSuretyData.isAirlineRegistered.call(accounts[2]);
    assert.equal(result, true, "Airline acc 2 should be registered");

    result = await config.flightSuretyData.isAirlineRegistered.call(accounts[3]);
    assert.equal(result, true, "Airline acc 3 should be registered");

    result = await config.flightSuretyData.isAirlineRegistered.call(accounts[4]);
    assert.equal(result, false, "Airline acc 4 should not be registered");
});
 
it('(airline) register an Airline using registerAirline() with 50% consensus', async () => {
    let newAirline = accounts[4];
    let result = await config.flightSuretyData.isAirlineRegistered.call(newAirline); 
    assert.equal(result, false, "Airline should not be registered");

    // add more 1 vote to new airline, and register it
    await config.flightSuretyApp.registerAirline(newAirline, {from: accounts[1]});

    result = await config.flightSuretyData.isAirlineRegistered.call(newAirline); 
    assert.equal(result, true, "Airline should be registered");
});

it(`(airline) fund airlines`, async function () {
    let airline = accounts[1];
    let fundValue = web3.utils.toWei("10", "ether");

    await config.flightSuretyApp.fundAirline({from: airline, value: fundValue});
    
    let result = await config.flightSuretyData.isAirlineFunded.call(airline, {from: config.flightSuretyApp.address});
    assert.equal(result, true, "Airline not funded");
});

});
