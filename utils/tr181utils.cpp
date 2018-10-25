/*
 * If not stated otherwise in this file or this component's Licenses.txt file the
 * following copyright and licenses apply:
 *
 * Copyright 2016 RDK Management
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
*/


/**
* @defgroup rfc
* @{
* @defgroup utils
* @{
**/

#include <unistd.h>
#include <error.h>

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <algorithm>
#include <iostream>
#include <string>
#include <fstream>
#include "rfcapi.h"
using namespace std;

char value_type = 'u';
char * value = NULL;
char * key = NULL;
REQ_TYPE mode = GET;
bool silent = true;

/**
* Returns the parameter type
*@param [in] paramName Name of the parameter for which type is requested
*@param [out] paramType Holds the value of paramtype if call is successful
*@returns true if the call succeded, false otherwise.
*/
static bool getParamType(char * const paramName, DATA_TYPE * paramType)
{
   RFC_ParamData_t param = {0};
   param.type = WDMP_NONE;
   WDMP_STATUS status = getRFCParameter(NULL, paramName, &param);

   if(param.type != WDMP_NONE)
   {
      cout << __FUNCTION__ << " >> Using the type provided by hostif, type= " << param.type << endl;
      *paramType = param.type;
      return true;
   }
   else
      cout << __FUNCTION__ << " >> Failed to retrieve : Reason " << getRFCErrorString(status) << endl;

   return false;
}

/**
* Convert the user input to enumeration
* @param [in] type character value, can be (s)tring, (i)integer or (b) boolean
*/
static DATA_TYPE convertType(char type)
{
   DATA_TYPE t;
   switch(type)
   {
      case 's':
         t = WDMP_STRING;
         break;
      case 'i':
         t = WDMP_INT;
         break;
      case 'b':
         t = WDMP_BOOLEAN;
         break;
      default:
         cout << __FUNCTION__ << " >>Invalid type entered, default to integer." << endl;
         t = WDMP_INT;
         break;
   }
   return t;
}

/**
* @param [in] param the object holding the details
*/
static void printParameterDetails(RFC_ParamData_t param )
{
   cout << __FUNCTION__ << " >>Get Operation successfull " <<endl;
   switch (param.type)
   {
      case WDMP_STRING :
         {
            cout << __FUNCTION__ << " >>Parameter Type ::String" << endl;
            cout << __FUNCTION__ << " >>Param value ::" << param.value << endl;
            cerr << param.value << endl;
         }
         break;
      case WDMP_INT :
         {
            cout << __FUNCTION__ << " >>Parameter Type ::Integer" << endl;
            int valueInt = atoi(param.value);
            cout << __FUNCTION__ << " >>Param value ::" << valueInt << endl;
            cerr << valueInt << endl;
         }
         break;
      case WDMP_UINT :
         {
            cout << __FUNCTION__ << " >>Parameter Type ::Unsigned Integer" << endl;
            unsigned int valueUint = atoi(param.value);
            cout << __FUNCTION__ << " >>Param value ::" << valueUint << endl;
            cerr << valueUint << endl;
         }
         break;
      case WDMP_BOOLEAN:
         {
            cout << __FUNCTION__ << " >>Parameter Type ::Boolean" << endl;
            bool valueBool = (0 == strncasecmp(param.value, "TRUE", 4)|| (isdigit(param.value[0]) && param.value[0] != '0' ));
            cout << __FUNCTION__ << " >>Param value ::" << valueBool << endl;
            cerr << valueBool << endl;
         }
         break;
      case WDMP_DATETIME:
         cout << __FUNCTION__ << " >>Parameter Type ::DateTime" << endl;
         cout << __FUNCTION__ << " >>Param value ::" << param.value << endl;
         cerr << param.value << endl;
         break;
      case WDMP_ULONG:
         {
            cout << __FUNCTION__ << " >>Parameter Type ::Unsigned Long" << endl;
            unsigned long valueUlong = atol(param.value);
            cout << __FUNCTION__ << " >>Param value ::" << valueUlong << endl;
            cerr << valueUlong << endl;
         }
         break;
   }
}

/**
* Retrieves the details about a property
* @param [in] paramName the parameter whose properties are retrieved
* @return 0 if succesfully retrieve value, 1 otherwise
*/
static int getAttribute(char * const paramName)
{
   RFC_ParamData_t param;
   WDMP_STATUS status = getRFCParameter(NULL, paramName, &param);

   if(status == WDMP_SUCCESS)
   {
       printParameterDetails(param);
   }
   else
   {
      cout << __FUNCTION__ << " >> Failed to retrieve : Reason " << getRFCErrorString(status) << endl;
   }

   return status;
}
/**
* Set the value for a property
* @param [in] paramName the name of the property
* @param [in] type type of property
* @param [in] value  value of the property
* @return 0 if success, 1 otherwise
*/
static int setAttribute(char * const paramName  ,char type, char * value)
{
   DATA_TYPE paramType;
   if (!getParamType (paramName, &paramType))
   {
      cout << __FUNCTION__ << " >>Failed to retrive parameter type from agent. Using provided values " <<endl;
      paramType = convertType(type);
   }

   WDMP_STATUS status = setRFCParameter(NULL,paramName, value, paramType);
   if (status != WDMP_SUCCESS)
      cout << __FUNCTION__ << " >> Set operation failed : " << getRFCErrorString(status) << endl;
   else
      cout << __FUNCTION__ << " >> Set operation success " << endl;

   return status;
}

/**
* Prints the usage of this app
*/
static void showusage(const char *exename)
{
   cout << "Usage : " << exename << "[-d] [-g] [-s] [-v value] ParamName\n" <<
      "-d debug enable\n-g get operation\n-s set operation\n-v value of parameter\n" <<
      "If -s option is set -v is mandatory, otherwise -g option is default\n" <<
      "eg:\n" << exename << " Device.DeviceInfo.X_RDKCENTRAL-COM_xBlueTooth.Enabled\n" <<
      exename << " -s -v XG1 Device.DeviceInfo.X_RDKCENTRAL-COM_PreferredGatewayType\n" <<
      endl;
}

int parseargs(int argc, char * argv[])
{
    int i = 1;
    while ( i < argc )
    {
        if(strncasecmp(argv[i], "-s", 2) == 0)
        {
            mode = SET;
            i ++;
        }
        else if(strncasecmp(argv[i], "-t", 2) == 0)
        {
            if (i + 1 < argc) {
                value_type = argv[i+1][0];
                i += 2;
            }
        }
        else if(strncasecmp(argv[i], "-v", 2) == 0)
        {
            if (i + 1 < argc) {
                value = argv[i+1];
                i += 2;
            }
        }
        else if(argv[i][0] != '-')
        {
            key = argv[i];
            i++;
        }
        else if(strncasecmp(argv[i], "-d", 2) == 0)
   {
            silent = false;
            i ++;
   }
        else
        {
       if(!silent)
               cout << __FUNCTION__ << " >>Ignoring input "<<argv[i]<<endl;
            i++;
        }
    }
    return  0;
}

int main(int argc, char *argv [])
{
   streambuf* stdout_handle;
   ofstream void_file;
   int retcode = 1;

   parseargs(argc,argv);

   if(NULL == key || (mode == SET && NULL == value))
   {
      showusage(argv[0]);
      exit(1);
   }

   if(silent)
   {
      void_file.open("/dev/null");
      stdout_handle = cout.rdbuf();

      cout.rdbuf(void_file.rdbuf());
   }

   if(mode != SET)
   {
      retcode = getAttribute(key);
   }
   else if( NULL != value){
      retcode = setAttribute(key,value_type, value);
   }

   //Redirecting again to avoid rfcapi prints
   if(silent)
   {
      cout.rdbuf(stdout_handle);
      void_file.close();
   }
   return retcode;
}
/** @} */
/** @} */

