# -*- coding: utf-8 -*-

'''
This requires Python 2.7. It was developed using Anaconda 2.30 (Python 2.7.10).
You should use Anaconda or be prepared to track down and install all of the
necessary Python packages.

The XML paths are given below for the Google bulk download.  Make
sure they haven't changed if you have problems.  This was written
for data from 2012 onward.  The tree was different in 2012 versus
2013 and 2014.  In particular, the XML path variable
'path_applicants' below changes.

All of the date formats are expected to be %Y%m%d

Created by David W. Dreisigmeyer 22 Oct 15
'''
import codecs
import csv
import glob
import json
import os
import re
import sys
import unicodedata
import zipfile
from datetime import datetime
from difflib import SequenceMatcher as SeqMatcher
from lxml import etree

cw_dir = sys.argv[2]
pat_num_re = re.compile(r'([A-Z]*)0*([0-9]+)')
date_format = '%Y%m%d'  # The dates are expected in %Y%m%d format
grant_year_re = re.compile('[a-z]{3,4}([0-9]{8})_wk[0-9]{2}')  # To get the grant year from the GBD file name
'''
CLOSE_CITY_SPELLINGS is a dictionary of zips of cities in the same state with a similar name.  It includes the
zips of the city itself.  This can be updated by each process which is why we didn't create it in launch.py.
'''
pathToJSON = 'parse_GBD/'
# CLOSE_CITY_SPELLINGS = {}
with open(pathToJSON + 'close_city_spellings.json') as json_data:
    CLOSE_CITY_SPELLINGS = json.load(json_data)


def clean_patnum(patnum):
    '''
    Removes extraneous zero padding
    '''
    pat_num = patnum.strip().upper()
    hold_pat_num = pat_num_re.match(pat_num).groups()
    pat_num_len = len(hold_pat_num[0] + hold_pat_num[1])
    zero_padding = '0' * (7 - pat_num_len)
    pat_num = hold_pat_num[0] + zero_padding + hold_pat_num[1]
    zero_padding = '0' * (8 - pat_num_len)
    xml_pat_num = hold_pat_num[0] + zero_padding + hold_pat_num[1]
    return xml_pat_num, pat_num


def keep_letters(x):
    '''
    Only keeps unicode letters and numbers along with the spaces.
    '''
    if unicodedata.category(x)[0] in ('L', 'N', 'Z'):  # alphanumeric
        return x
    else:  # crap
        return u''


def clean_it(in_str):
    if isinstance(in_str, str):
        encoded_str = in_str.decode('utf8')
    else:
        return ''
    out_str = encoded_str
    out_str = ''.join(keep_letters(x) for x in out_str)
    out_str = out_str.upper()
    out_str = ' '.join(out_str.split())
    return out_str


def clean_up(applicant, xml_path):
    '''
    Clean up the string
    '''
    applicant_text = applicant.find(xml_path).text
    applicant_text = clean_it(applicant_text)
    # Replace utf-8 characters with their closest ascii
    applicant_text = unicodedata.normalize('NFKD', applicant_text)
    applicant_text = applicant_text.encode('ascii', 'ignore')
    applicant_text = re.sub('\s*LATE\s+OF\s*', '', applicant_text)
    applicant_text = re.sub('[^a-zA-Z0-9 ]+', '', applicant_text).upper()
    return applicant_text.strip()


def split_first_name(in_name):
    '''
    Get middle name out of first name
    '''
    holder = in_name.split(' ', 1)
    if len(holder) > 1:
        return holder[0], holder[1]
    else:
        return in_name, ''


def split_name_suffix(in_name):
    '''
    Takes the suffix off the last name
    '''
    # These are the generational suffixes.
    suffix_list = [
        'SR', 'SENIOR', 'I', 'FIRST', '1ST',
        'JR', 'JUNIOR', 'II', 'SECOND', '2ND',
        'THIRD', 'III', '3RD',
        'FOURTH', 'IV', '4TH',
        'FIFTH', 'V', '5TH',
        'SIXTH', 'VI', '6TH',
        'SEVENTH', 'VII', '7TH',
        'EIGHTH', 'VIII', '8TH',
        'NINTH' 'IX', '9TH',
        'TENTH', 'X', '10TH'
    ]
    holder = in_name.rsplit(' ', 2)
    if len(holder) == 1:  # includes empty string
        return in_name, ''
    elif len(holder) == 2:
        if holder[1] in suffix_list:
            return holder[0], holder[1]
        else:
            return in_name, ''
    elif holder[2] in suffix_list:
        if holder[1] == 'THE':
            return holder[0], holder[2]
        else:
            last_nm = holder[0] + ' ' + holder[1]
            return last_nm, holder[2]
    else:
        return in_name, ''


def get_zip3(applicant_state, applicant_city,
             zip3_json, cleaned_cities_json, inventor_names_json,
             last_name=None, first_name=None, middle_initial=None,
             flag=0):
    '''
    Attempts to find a zip3 from an applicant's city and state information.
    flag is for when we call this function again and avoid infinite recursion.
    '''
    global CLOSE_CITY_SPELLINGS
    possible_zip3s = set()
    possible_cities = [applicant_city]
    cleaned_cities = cleaned_cities_json.get(applicant_state)
    if cleaned_cities:
        for hold_city, spellings in cleaned_cities.iteritems():
            if hold_city not in possible_cities:
                if applicant_city[:20] in spellings:
                    possible_cities.append(hold_city)
    city_names = zip3_json.get(applicant_state)
    close_city_names = CLOSE_CITY_SPELLINGS.get(applicant_state)
    if close_city_names:
        close_city_names_keys = close_city_names.keys()
    else:
        close_city_names_keys = []
    for alias in possible_cities:
        if alias in close_city_names_keys:  # is the name ok?
            possible_zip3s.update(close_city_names[alias])
            continue
        if applicant_state not in CLOSE_CITY_SPELLINGS.keys():  # is this a real state?
            continue
        CLOSE_CITY_SPELLINGS[applicant_state][alias] = set()  # this isn't there
        if city_names:  # this may be a new misspelling, which we're going to check for now
            for city, zips in city_names.iteritems():
                str_match = SeqMatcher(None, alias, city)
                if str_match.ratio() >= 0.9:  # good enough match
                    CLOSE_CITY_SPELLINGS[applicant_state][alias].update(zips)
                    possible_zip3s.update(zips)
    # If we couldn't find a zip3 we'll see if we can correct the city, state or country
    if not possible_zip3s and not flag:
        l_name = last_name[:20]
        f_name = first_name[:15]
        if middle_initial:
            middle_initial = middle_initial[0]
        locations = []
        try:
            locations = inventor_names_json.get(l_name).get(f_name).get(middle_initial)
        except StandardError:  # possible the name isn't in our JSON file
            pass
        for location in locations:
            app_city = applicant_city[:20]
            app_state = applicant_state
            possible_city = location['city']
            possible_state = location['state']
            # Foreign national
            if len(possible_state) == 3 and possible_state[2] == 'X':
                continue
            # We only allow the city OR the state to be incorrect.
            # Otherwise we could be finding a different inventor with
            # the same name with a relatively high probability.
            # The state is wrong (seems to happen more often so it's first)
            elif app_city == possible_city and app_state != possible_state:
                app_state = possible_state
            # The city is wrong (seems to happen less often so it's second)
            elif app_city != possible_city and app_state == possible_state:
                app_city = possible_city
            # Nothing is wrong
            else:
                continue

            hold_corrected_zip3 = get_zip3(app_state, app_city,
                                           zip3_json, cleaned_cities_json, inventor_names_json,
                                           flag=1)
            possible_zip3s.update(hold_corrected_zip3)
    return possible_zip3s


def assign_zip3(files, zip3_json, cleaned_cities_json, inventor_names_json):
    '''
    '''
    # init_close_city_spellings(zip3_json, cleaned_cities_json)
    for in_file in files:
        zip3_thread(in_file, zip3_json, cleaned_cities_json, inventor_names_json)


def zip3_thread(in_file, zip3_json, cleaned_cities_json, inventor_names_json):
    folder_name = os.path.splitext(os.path.basename(in_file))[0]
    # Get data in and ready
    folder_path = cw_dir + '/holdData/' + folder_name + '/'
    os.umask(0002)
    os.mkdir(folder_path)
    zipped_file = zipfile.ZipFile(in_file, 'r')
    zipped_file.extractall(folder_path)
    zipped_file.close()
    xml_split = glob.glob(folder_path + '/*.xml')
    grant_year_gbd = int(grant_year_re.match(folder_name).group(1)[:4])
    # Run the queries
    for xmlDoc in xml_split:
        try:
            xml_doc_thread(xmlDoc, grant_year_gbd, zip3_json, cleaned_cities_json, inventor_names_json)
        except Exception as e:
            print(in_file + ': Exception ' + str(e) + ' in xmlDoc ' + xmlDoc)
            pass
    # Clean things up
    os.system('rm -rf ' + folder_path)


# noinspection PyUnboundLocalVariable
def xml_doc_thread(xml_doc, grant_year_gbd, zip3_json, cleaned_cities_json, inventor_names_json):
    '''
    These are the XML paths we use to extract the data.
    Note: if the path is rel_path_something_XXX then this is a path that is
    relative to the path given by path_something.
    There were some slight changes to the paths from the 2005 - 2012 years and the
    2013 - present years.  There were major changes from the 2002 - 2004 years.
    All of the patent XML files prior to 2002 were constructed fomr the Google
    Bulk Download *.dat files.
    '''
    validator = etree.XMLParser(dtd_validation=True)
    if grant_year_gbd > 2004:
        path_patent_number = 'us-bibliographic-data-grant/publication-reference/document-id/doc-number'
        path_app_date = 'us-bibliographic-data-grant/application-reference/document-id/date'
        path_applicants_alt1 = 'us-bibliographic-data-grant/parties/applicants/'
        path_applicants_alt2 = 'us-bibliographic-data-grant/us-parties/us-applicants/'
        path_assignees = 'us-bibliographic-data-grant/assignees/'
        rel_path_applicants_last_name = 'addressbook/last-name'
        rel_path_applicants_first_name = 'addressbook/first-name'
        rel_path_applicants_city = 'addressbook/address/city'
        rel_path_applicants_state = 'addressbook/address/state'
        rel_path_assignees_state = 'addressbook/address/state'
        path_inventors_alt1 = 'us-bibliographic-data-grant/parties/inventors/'
        path_inventors_alt2 = 'us-bibliographic-data-grant/us-parties/inventors/'
        rel_path_inventors_last_name = 'addressbook/last-name'
        rel_path_inventors_first_name = 'addressbook/first-name'
        rel_path_inventors_city = 'addressbook/address/city'
        rel_path_inventors_state = 'addressbook/address/state'
    elif 2001 < grant_year_gbd < 2005:
        path_patent_number = 'SDOBI/B100/B110/DNUM/PDAT'
        path_app_date = 'SDOBI/B200/B220/DATE/PDAT'
        path_applicants_alt1 = 'SDOBI/B700/B720'
        path_applicants_alt2 = ''
        path_assignees = 'SDOBI/B700/B730'
        rel_path_applicants_last_name = './B721/PARTY-US/NAM/SNM/STEXT/PDAT'
        rel_path_applicants_first_name = './B721/PARTY-US/NAM/FNM/PDAT'
        rel_path_applicants_city = './B721/PARTY-US/ADR/CITY/PDAT'
        rel_path_applicants_state = './B721/PARTY-US/ADR/STATE/PDAT'
        rel_path_assignees_state = './B731/PARTY-US/ADR/STATE/PDAT'
    elif grant_year_gbd < 2002:
        path_patent_number = 'WKU'
        path_app_date = 'APD'
        path_applicants_alt1 = 'INVTS'
        path_applicants_alt2 = ''
        path_assignees = 'ASSGS/'
        rel_path_applicants_last_name = 'LN'
        rel_path_applicants_first_name = 'FN'
        rel_path_applicants_city = 'CTY'
        rel_path_applicants_state = 'STA'
        rel_path_assignees_state = 'STA'
    else:
        raise UserWarning('Incorrect grant year: ' + str(grant_year_gbd))
    try:
        if grant_year_gbd > 2001:
            root = etree.parse(xml_doc, validator)
        else:
            root = etree.parse(xml_doc)
    except StandardError as e:
        print(str(e) + ': could not parse patent document ' + str(xml_doc))
        return
    if root.find(path_applicants_alt1) is not None:
        path_applicants = path_applicants_alt1
    elif root.find(path_applicants_alt2) is not None:
        path_applicants = path_applicants_alt2
    else:
        return
    try:  # to get patent number
        patent_number = root.find(path_patent_number).text
        patent_number, uspto_pat_num = clean_patnum(patent_number)
    except StandardError as e:
        print(str(e) + ': could not get patent number for ' + str(xml_doc))
        return
    try:  # to get the application date
        app_date = root.find(path_app_date).text
        app_year = str(datetime.strptime(app_date, date_format).year)
    except StandardError as e:
        print(str(e) + ': incorrectly formatted application date for patent ' + patent_number + ' in ' + str(xml_doc))
        return
    try:
        assignees = root.findall(path_assignees)
    except StandardError as e:
        print(str(e) + ': incorrectly formatted assignees for patent ' + patent_number + ' in ' + str(xml_doc))
        return
    assignee_state = set()
    if assignees:
        for assignee in assignees:
            try:  # to get an assignee state
                assignee_state_hold = assignee.find(rel_path_assignees_state).text
                assignee_state_hold = re.sub('[^a-zA-Z]+', '', assignee_state_hold).upper()
                assignee_state.add(assignee_state_hold)
            except StandardError:  # don't worry if you can't
                pass
    if not assignee_state:
        assignee_state.add('')  # we need a non-empty assignee_state below
    applicants = root.findall(path_applicants)
    if not applicants:
        print('No applicants on patent : ' + patent_number + ' in ' + str(xml_doc))
        return
    number_applicants_to_process = len(applicants)
    applicant_counter = 0
    for applicant in applicants:
        applicant_counter += 1
        csv_line = [patent_number, uspto_pat_num, app_year, grant_year_gbd]
        try:
            applicant_city = clean_up(applicant, rel_path_applicants_city)
            csv_line.append(applicant_city)
        except StandardError:
            applicant_city = ''
            csv_line.append('')  # Don't worry if it's not there
        try:
            applicant_state = applicant.find(rel_path_applicants_state).text
            applicant_state = re.sub('[^a-zA-Z]+', '', applicant_state).upper()
            csv_line.append(applicant_state)
        except StandardError:  # not a US inventor
            continue
        try:  # to get all of the applicant data
            try:  # For 2005 and later patents
                applicant_sequence_num = applicant.get('sequence')
            except StandardError:  # For pre-2005 patents
                applicant_sequence_num = ''
            applicant_last_name = clean_up(applicant, rel_path_applicants_last_name)
            applicant_last_name, applicant_suffix = split_name_suffix(applicant_last_name)
            applicant_first_name = clean_up(applicant, rel_path_applicants_first_name)
            applicant_first_name, applicant_middle_name = split_first_name(applicant_first_name)
            csv_line.append(applicant_sequence_num)
            csv_line.append(applicant_counter)
            csv_line.extend((applicant_last_name, applicant_suffix, applicant_first_name, applicant_middle_name))
            applicant_last_name = applicant_last_name + ' ' + applicant_suffix  # For possible_zip3s call below
        except StandardError:  # something's wrong so go to the next applicant
            continue
        possible_zip3s = get_zip3(applicant_state, applicant_city,
                                  zip3_json, cleaned_cities_json, inventor_names_json,
                                  applicant_last_name, applicant_first_name, applicant_middle_name)
        if not possible_zip3s:  # Didn't find a zip3?
            possible_zip3s.add('')  # We'll at least have the city/state
        # ## Yes this should be ASCII
        csv_file = codecs.open('./outData/zip3s_' + app_year + '.csv', 'a', 'ascii')
        csv_writer = csv.writer(csv_file)
        # Write results
        for new_zip3 in possible_zip3s:
            for asg_st in assignee_state:
                hold_csv_line = list(csv_line)  # copy csv_line...
                hold_csv_line.append(new_zip3)  # ... so we can append without fear!
                hold_csv_line.append(asg_st)
                csv_writer.writerow(hold_csv_line)
    # make sure we at least tried to get every applicant
    if number_applicants_to_process != applicant_counter:
        print('WARNING: Did not try to process every applicant on patent ' + patent_number)
    # I just quickly put this on to take care of 2005 and later XML files
    # with incorrect applicant information.  Assignee info was used instead
    # of inventor
    if grant_year_gbd > 2004:
        if root.find(path_inventors_alt1) is not None:
            path_inventors = path_inventors_alt1
        elif root.find(path_inventors_alt2) is not None:
            path_inventors = path_inventors_alt2
        else:
            return
        applicants = root.findall(path_inventors)
        if not applicants:
            print('No applicants on patent : ' + patent_number + ' in ' + str(xml_doc))
            return
        number_applicants_to_process = len(applicants)
        applicant_counter = 0
        for applicant in applicants:
            applicant_counter += 1
            csv_line = [patent_number, uspto_pat_num, app_year, grant_year_gbd]
            try:
                applicant_city = clean_up(applicant, rel_path_inventors_city)
                csv_line.append(applicant_city)
            except StandardError:
                applicant_city = ''
                csv_line.append('')  # Don't worry if it's not there
            try:
                applicant_state = applicant.find(rel_path_inventors_state).text
                applicant_state = re.sub('[^a-zA-Z]+', '', applicant_state).upper()
                csv_line.append(applicant_state)
            except StandardError:  # not a US inventor
                continue
            try:  # to get all of the applicant data
                try:  # For 2005 and later patents
                    applicant_sequence_num = applicant.get('sequence')
                except StandardError:  # For pre-2005 patents
                    applicant_sequence_num = ''
                applicant_last_name = clean_up(applicant, rel_path_inventors_last_name)
                applicant_last_name, applicant_suffix = split_name_suffix(applicant_last_name)
                applicant_first_name = clean_up(applicant, rel_path_inventors_first_name)
                applicant_first_name, applicant_middle_name = split_first_name(applicant_first_name)
                csv_line.append(applicant_sequence_num)
                csv_line.append(applicant_counter)
                csv_line.extend((applicant_last_name, applicant_suffix, applicant_first_name, applicant_middle_name))
                applicant_last_name = applicant_last_name + ' ' + applicant_suffix  # For possible_zip3s call below
            except StandardError:  # something's wrong so go to the next applicant
                continue
            possible_zip3s = get_zip3(applicant_state, applicant_city,
                                      zip3_json, cleaned_cities_json, inventor_names_json,
                                      applicant_last_name, applicant_first_name, applicant_middle_name)
            if not possible_zip3s:  # Didn't find a zip3?
                possible_zip3s.add('')  # We'll at least have the city/state
            # ## Yes this should be ASCII
            csv_file = codecs.open('./outData/zip3s_' + app_year + '.csv', 'a', 'ascii')
            csv_writer = csv.writer(csv_file)
            # Write results
            for new_zip3 in possible_zip3s:
                for asg_st in assignee_state:
                    hold_csv_line = list(csv_line)  # copy csv_line...
                    hold_csv_line.append(new_zip3)  # ... so we can append without fear!
                    hold_csv_line.append(asg_st)
                    csv_writer.writerow(hold_csv_line)
        # make sure we at least tried to get every applicant
        if number_applicants_to_process != applicant_counter:
            print('WARNING: Did not try to process every applicant on patent ' + patent_number)
