package org.openbmp;

import org.openbmp.api.helpers.IpAddr;

import junit.framework.Test;
import junit.framework.TestCase;
import junit.framework.TestSuite;


/**
 * Unit test for simple ConsumerApp.
 */
public class ConsumerRunnableAppTest
    extends TestCase
{
    /**
     * Create the test case
     *
     * @param testName name of the test case
     */
    public ConsumerRunnableAppTest(String testName)
    {
        super(testName);
    }

    /**
     * @return the suite of tests being tested
     */
    public static Test suite()
    {
        return new TestSuite( ConsumerRunnableAppTest.class );
    }

    public void testIpToBits()
    {
        System.out.println("Testing IP 10.1.1.248 = " + IpAddr.getIpBits("10.1.1.248"));
        assertTrue(IpAddr.getIpBits("10.1.1.248").equals("00001010000000010000000111111000"));
    }

}
