/*
 * Copyright (c) 2018-2022 Cisco Systems, Inc. and others.  All rights reserved.
 */
package org.openbmp.psqlquery;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.openbmp.api.parsed.message.MsgBusFields;


/**
 * abstract class to define methods that will contain SQL query for each Object. 
 * @author mmaredia
 *
 */
public abstract class Query {
	
	
	protected List<Map<String, Object>> rowMap;
	
	/**
	 * lookup value in the rowMap for a header, return the default if absent. 
	 * @param header
	 * @param index
	 * @return Object
	 */
	protected Object lookupValue(MsgBusFields header, int index){
    	
    	if(rowMap==null || rowMap.get(index)==null)
    		return header.getDefaultValue();
    	
		Object value = rowMap.get(index).get(header.getName());
    	
    	return value==null ? header.getDefaultValue() : value;
    	
    }
	
	
    /**
     * Generate MySQL insert/update statement, sans the values
     *
     * @return Two strings are returned
     *      0 = Insert statement string up to VALUES keyword
     *      1 = ON DUPLICATE ...  or empty if not used.
     */
    public abstract String[] genInsertStatement();

    /**
     * Generate values map.
     *
     * @return Map; Key is the record hash_id and value is the statement for SQL bulk insert.
     */
    public abstract Map<String, String> genValuesStatement();

}
