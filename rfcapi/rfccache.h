/*
 * If not stated otherwise in this file or this component's Licenses.txt file the
 * following copyright and licenses apply:
 *
 * Copyright 2018 RDK Management
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

#ifndef RFCCACHE_H
#define RFCCACHE_H

#include <unordered_map>
#include <string>

using namespace std;

#define LOG_RFCAPI  "LOG.RDK.RFCAPI"

typedef enum _RFC_Cache_Type_t 
{
  RFC_VAR,
  RFC_TR181_STORE
} RFC_Cache_Type_t;

class RFCCache
{
public:
    bool initCache(RFC_Cache_Type_t rfcCacheType);
    string  getValue(const string &key);

private:
    string m_filename;
    bool initDone;
    std::unordered_map<std::string, std::string> m_dict;

    bool initRFCDataFileName(RFC_Cache_Type_t rfcCacheType);
    bool loadRFCDataIntoCache();
};

#endif // RFCCACHE_H
